module Crux::Git
  # Per-repo outcome of a batch pull, used to build the compact summary line.
  struct RepoOutcome
    # Classification of what happened to a single repository.
    enum Kind
      Cloned   # repo was absent locally and has now been cloned
      Updated  # repo existed and fast-forwarded to new commits
      UpToDate # repo existed and was already current
      Failed   # clone or pull failed, or config was unusable
    end

    getter name : String
    getter kind : Kind
    getter detail : String

    def initialize(@name : String, @kind : Kind, @detail : String = "")
    end

    def failed? : Bool
      kind.failed?
    end
  end

  # Orchestrates `crux git batch pull`: for every repo in the batch list, clone
  # it when missing or fast-forward pull it when present, all in parallel, and
  # collect a compact per-repo outcome.
  #
  # Depends only on the abstract `Runner` and the parsed config, so the whole
  # pipeline is exercised in tests with a fake runner and no filesystem clones.
  class BatchPuller
    def initialize(@runner : Runner, @batch : BatchConfig, @profiles : ProfilesConfig)
    end

    # Processes every repo concurrently and returns outcomes in input order.
    #
    # Each repo runs in its own fiber; git subprocesses yield to the event loop
    # while they wait on IO, so the pulls genuinely overlap. Results are keyed
    # by index to preserve the configured ordering regardless of finish order.
    def run : Array(RepoOutcome)
      repos = @batch.repos
      return [] of RepoOutcome if repos.empty?

      channel = Channel({Int32, RepoOutcome}).new

      repos.each_with_index do |repo, index|
        spawn do
          channel.send({index, process(repo)})
        end
      end

      # Collect by index, then materialize in configured order regardless of
      # the order fibers happened to finish in.
      collected = Hash(Int32, RepoOutcome).new
      repos.size.times do
        index, outcome = channel.receive
        collected[index] = outcome
      end

      Array.new(repos.size) { |index| collected[index] }
    end

    # Resolves the profile, picks clone vs pull, and classifies the result for a
    # single repository. Never raises: every failure becomes a Failed outcome so
    # one bad repo cannot abort the whole batch.
    private def process(repo : RepoEntry) : RepoOutcome
      profile = @profiles.find(repo.profile)
      unless profile
        return RepoOutcome.new(repo.dir_name, RepoOutcome::Kind::Failed, "unknown profile '#{repo.profile}'")
      end

      env = profile.git_env
      dest = File.join(@batch.expanded_root, repo.dir_name)

      if Dir.exists?(File.join(dest, ".git"))
        pull_existing(repo, dest, env)
      else
        clone_fresh(repo, dest, env)
      end
    rescue ex : Exception
      RepoOutcome.new(repo.dir_name, RepoOutcome::Kind::Failed, ex.message || "unexpected error")
    end

    # Clones a repository that is not yet present locally.
    private def clone_fresh(repo : RepoEntry, dest : String, env : Hash(String, String)?) : RepoOutcome
      result = @runner.clone(repo.url, dest, env)
      if result.success?
        RepoOutcome.new(repo.dir_name, RepoOutcome::Kind::Cloned, "cloned from #{repo.url}")
      else
        RepoOutcome.new(repo.dir_name, RepoOutcome::Kind::Failed, first_line(result.error))
      end
    end

    # Fast-forward pulls a repository that already exists, then summarizes the
    # delta between the pre- and post-pull HEAD.
    private def pull_existing(repo : RepoEntry, dest : String, env : Hash(String, String)?) : RepoOutcome
      before = @runner.rev_parse(dest)
      result = @runner.pull(dest, env)

      unless result.success?
        return RepoOutcome.new(repo.dir_name, RepoOutcome::Kind::Failed, first_line(result.error))
      end

      after = @runner.rev_parse(dest)

      if before && after && before == after
        return RepoOutcome.new(repo.dir_name, RepoOutcome::Kind::UpToDate, "already up to date")
      end

      RepoOutcome.new(repo.dir_name, RepoOutcome::Kind::Updated, change_summary(dest, before, after))
    end

    # Builds a compact "N commits, <shortstat>" summary for a pulled range.
    # Falls back to a generic message when the boundary commits are unknown.
    private def change_summary(dest : String, before : String?, after : String?) : String
      return "updated" unless before && after

      range = "#{before}..#{after}"
      count = @runner.count_commits(dest, range)
      commit_label = count == 1 ? "1 commit" : "#{count} commits"

      if stat = @runner.shortstat(dest, range)
        "#{commit_label}, #{stat}"
      else
        commit_label
      end
    end

    # Returns the first non-empty line of `text`, trimmed, for tidy error output.
    private def first_line(text : String) : String
      line = text.each_line.find { |candidate| !candidate.strip.empty? }
      (line || text).strip
    end
  end
end
