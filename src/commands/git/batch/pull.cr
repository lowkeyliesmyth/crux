module Crux::Commands
  class Pull < Batch
    property git : Crux::Git::Runner

    # Injectable runner keeps the orchestration testable without real clones.
    def initialize(@git : Crux::Git::Runner = Crux::Git::RealGit.new)
      super()
    end

    def setup : Nil
      @name = "pull"
      @summary = "clone missing and fast-forward existing batch repos in parallel"
      @description = <<-DESC
        Reads the batch repo list and clones any repositories not yet present
        locally, then fast-forward pulls the ones that already are, in parallel.

        Prints a compact per-repo summary of what changed. Repos are bound to a
        git profile so the correct identity (ssh key) is used per repository.

        Config files:
          profiles: #{Crux::Git.profiles_path}
          batch:    #{Crux::Git.batch_path}
        DESC

      add_usage "crux git batch pull"
    end

    def command_pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      unless @git.installed?
        error "'git' executable not found on PATH"
        error "Install git and try again"
        exit_program 1
      end
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      profiles = Crux::Git::ProfilesConfig.load
      batch = Crux::Git::BatchConfig.load

      if batch.repos.empty?
        info "No repositories in the batch list. Nothing to do."
        return
      end

      info "Processing #{batch.repos.size} #{batch.repos.size == 1 ? "repository" : "repositories"} under #{batch.expanded_root}"

      puller = Crux::Git::BatchPuller.new(@git, batch, profiles)
      outcomes = puller.run

      outcomes.each { |outcome| report(outcome) }
      summarize(outcomes)
    rescue ex : Crux::Git::ConfigError
      error "#{"Config error:".colorize.bold}"
      error "\t#{ex.message}"
      exit_program 1
    end

    def post_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    # Prints a single per-repo result line with a status-colored marker.
    private def report(outcome : Crux::Git::RepoOutcome) : Nil
      marker, name_color = case outcome.kind
                           in Crux::Git::RepoOutcome::Kind::Cloned   then {"+", :green}
                           in Crux::Git::RepoOutcome::Kind::Updated  then {"^", :green}
                           in Crux::Git::RepoOutcome::Kind::UpToDate then {"=", :blue}
                           in Crux::Git::RepoOutcome::Kind::Failed   then {"!", :red}
                           end

      stdout << "  " << marker.colorize(name_color) << " " << outcome.name.colorize(name_color).bold
      stdout << "  " << outcome.detail unless outcome.detail.empty?
      stdout << '\n'
    end

    # Prints a one-line tally and exits non-zero if any repo failed.
    private def summarize(outcomes : Array(Crux::Git::RepoOutcome)) : Nil
      cloned = outcomes.count(&.kind.cloned?)
      updated = outcomes.count(&.kind.updated?)
      current = outcomes.count(&.kind.up_to_date?)
      failed = outcomes.count(&.failed?)

      stdout << '\n'
      info "#{"Done:".colorize.bold.green} #{cloned} cloned, #{updated} updated, #{current} up to date, #{failed} failed"
      exit_program 1 if failed > 0
    end
  end
end
