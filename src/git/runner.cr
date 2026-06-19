module Crux::Git
  # Outcome of a single git invocation.
  #
  # Captures the exit code and the buffered stdout/stderr so callers can branch
  # on success and surface diagnostics without re-running the process.
  struct Result
    getter exit_code : Int32
    getter output : String
    getter error : String

    def initialize(@exit_code : Int32, @output : String, @error : String)
    end

    def success? : Bool
      @exit_code == 0
    end
  end

  # Abstract collaborator for git operations.
  #
  # All higher level behavior (clone, pull, commit, inspection) is expressed in
  # terms of the single abstract `run` primitive so that tests only need to
  # override `run` with a fake to exercise the orchestration logic without ever
  # touching a real repository or the network.
  abstract class Runner
    # Returns true if the git executable is available on PATH.
    abstract def installed? : Bool

    # Runs git with `args`, optionally inside `chdir`, with extra `env`, and an
    # optional `input` string piped to git's stdin. Returns a buffered `Result`.
    abstract def run(
      args : Array(String),
      chdir : String? = nil,
      env : Hash(String, String)? = nil,
      input : String? = nil,
    ) : Result

    # Clones `url` into `dest`. `env` carries any per-profile overrides such as
    # GIT_SSH_COMMAND so the correct identity is used during transport.
    def clone(url : String, dest : String, env : Hash(String, String)? = nil) : Result
      run(["clone", url, dest], env: env)
    end

    # Fast-forward pulls the repository checked out at `dir`.
    #
    # `--ff-only` keeps batch pulls predictable: a repo that would require a
    # merge or rebase is reported as a failure rather than silently mutating
    # local history.
    def pull(dir : String, env : Hash(String, String)? = nil) : Result
      run(["pull", "--ff-only"], chdir: dir, env: env)
    end

    # Returns the resolved object id for `ref` in `dir`, or nil on failure.
    def rev_parse(dir : String, ref : String = "HEAD") : String?
      result = run(["rev-parse", ref], chdir: dir)
      result.success? ? result.output.strip : nil
    end

    # Counts the commits contained in `range` (e.g. "old..new") for `dir`.
    def count_commits(dir : String, range : String) : Int32
      result = run(["rev-list", "--count", range], chdir: dir)
      return 0 unless result.success?
      result.output.strip.to_i? || 0
    end

    # Returns git's `--shortstat` summary for `range`, or nil when there is no
    # diff (or the command fails).
    def shortstat(dir : String, range : String) : String?
      result = run(["diff", "--shortstat", range], chdir: dir)
      return nil unless result.success?
      summary = result.output.strip
      summary.empty? ? nil : summary
    end

    # Creates a commit in `dir` using `message`. The message is piped via stdin
    # (`-F -`) so arbitrary multi-line bodies survive without shell quoting.
    # When `all` is true, tracked modifications are staged first (`--all`).
    def commit(dir : String, message : String, all : Bool = false) : Result
      args = ["commit"]
      args << "--all" if all
      args << "--file" << "-"
      run(args, chdir: dir, input: message)
    end

    # Returns true if `dir` has changes already staged for commit.
    def staged_changes?(dir : String) : Bool
      # `diff --cached --quiet` exits non-zero precisely when staged changes exist.
      !run(["diff", "--cached", "--quiet"], chdir: dir).success?
    end

    # Returns the repository root for `dir`, or nil if it is not a work tree.
    def toplevel(dir : String) : String?
      result = run(["rev-parse", "--show-toplevel"], chdir: dir)
      result.success? ? result.output.strip : nil
    end
  end

  # Concrete `Runner` that shells out to the locally installed git binary.
  #
  # This is the only place in the git namespace that touches a subprocess; every
  # other component depends on the abstract `Runner` so behavior stays testable.
  class RealGit < Runner
    def installed? : Bool
      !!Process.find_executable("git")
    end

    def run(
      args : Array(String),
      chdir : String? = nil,
      env : Hash(String, String)? = nil,
      input : String? = nil,
    ) : Result
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      input_io = input ? IO::Memory.new(input) : Process::Redirect::Close

      status = Process.run(
        "git",
        args,
        env: env,
        input: input_io,
        output: stdout_io,
        error: stderr_io,
        chdir: chdir,
      )

      Result.new(status.exit_code, stdout_io.to_s, stderr_io.to_s)
    end
  end
end
