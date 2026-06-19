require "../../spec_helper"
require "../../support/fake_git"
require "file_utils"

# Wires up a Commit command with a fake git and scripted stdin, returning the
# captured stdout. Stubs the three git lookups the command performs up front:
# toplevel (rev-parse), staged-change detection (diff), and the commit itself.
private def run_commit(repo_root : String, script : String, git : FakeGit) : String
  git.stub("rev-parse", ok_result(repo_root)) # toplevel lookup
  git.stub("diff", fail_result)               # non-zero => staged changes exist
  git.stub("commit", ok_result)

  cmd = Crux::Commands::Commit.new(git)
  cmd.stdin = IO::Memory.new(script)
  output = IO::Memory.new
  cmd.stdout = output
  cmd.execute([] of String)
  output.to_s
end

describe Crux::Commands::Commit do
  repo_root = ""

  before_each do
    repo_root = File.join(Dir.tempdir, "crux_commit_#{Time.utc.to_unix_ms}_#{rand(10000)}")
    Dir.mkdir_p(repo_root)
  end

  after_each do
    FileUtils.rm_rf(repo_root) if Dir.exists?(repo_root)
  end

  it "builds and commits a conventional message from the prompts" do
    git = FakeGit.new
    # type, scope(empty), ticket(empty), subject, body(empty), breaking(n), confirm(y)
    output = run_commit(repo_root, "feat\n\n\nadd thing\n\nn\ny\n", git)

    git.called?("commit").should be_true
    git.inputs.compact.should contain("feat: add thing")
    output.should contain("Committed:")
  end

  it "enforces a required ticket and validates its pattern" do
    File.write(File.join(repo_root, Crux::Git::CommitConfig::FILE_NAME),
      "ticket:\n  required: true\n  pattern: '[A-Z]+-\\d+'\ntypes:\n  - feat\n  - fix\n")

    git = FakeGit.new
    # type, scope, ticket(bad -> reprompt), ticket(valid), subject, body, breaking(n), confirm(y)
    run_commit(repo_root, "feat\n\nbad\nJIRA-9\nfix the bug\n\nn\ny\n", git)

    git.inputs.compact.should contain("feat: JIRA-9 fix the bug")
  end

  it "aborts without committing when the user declines confirmation" do
    git = FakeGit.new
    output = run_commit(repo_root, "feat\n\n\nadd thing\n\nn\nn\n", git)

    git.called?("commit").should be_false
    output.should contain("Aborted")
  end
end
