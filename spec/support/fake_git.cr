require "../../src/crux"

# Test double for Crux::Git::Runner.
#
# Overrides only the `run` primitive (and `installed?`) so the real high-level
# wrappers — clone, pull, rev_parse, commit, etc. — are exercised against
# scripted results. Calls are recorded for assertions, and per-subcommand result
# queues let a test return different values across repeated calls (e.g. the two
# `rev-parse HEAD` lookups that bracket a pull).
class FakeGit < Crux::Git::Runner
  property? installed : Bool = true
  getter calls = [] of Array(String)
  getter inputs = [] of String?
  getter envs = [] of Hash(String, String)?

  @queues = Hash(String, Array(Crux::Git::Result)).new

  def installed? : Bool
    @installed
  end

  # Queues one or more results to be returned, in order, for invocations whose
  # first argument equals `subcommand`.
  def stub(subcommand : String, *results : Crux::Git::Result) : Nil
    (@queues[subcommand] ||= [] of Crux::Git::Result).concat(results.to_a)
  end

  def run(
    args : Array(String),
    chdir : String? = nil,
    env : Hash(String, String)? = nil,
    input : String? = nil,
  ) : Crux::Git::Result
    @calls << args
    @inputs << input
    @envs << env

    queue = @queues[args.first]?
    if queue && !queue.empty?
      queue.shift
    else
      Crux::Git::Result.new(0, "", "")
    end
  end

  # Convenience: did any invocation start with `subcommand`?
  def called?(subcommand : String) : Bool
    @calls.any? { |args| args.first? == subcommand }
  end
end

# Builds a successful Result with the given stdout.
def ok_result(output : String = "") : Crux::Git::Result
  Crux::Git::Result.new(0, output, "")
end

# Builds a failing Result with the given stderr and exit code.
def fail_result(error : String = "boom", code : Int32 = 1) : Crux::Git::Result
  Crux::Git::Result.new(code, "", error)
end
