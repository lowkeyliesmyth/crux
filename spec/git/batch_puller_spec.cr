require "../spec_helper"
require "../support/fake_git"
require "file_utils"

# Builds a ProfilesConfig containing a single keyless "default" profile.
private def profiles_with_default : Crux::Git::ProfilesConfig
  Crux::Git::ProfilesConfig.from_kyaml(<<-KYAML)
    profiles:
      - name: default
    KYAML
end

# Builds a BatchConfig rooted at `root` for the given repo url/profile pairs.
private def batch_config(root : String, repos : Array({String, String})) : Crux::Git::BatchConfig
  body = String.build do |io|
    io << "root: " << root << '\n'
    io << "repos:\n"
    repos.each do |(url, profile)|
      io << "  - url: " << url << '\n'
      io << "    profile: " << profile << '\n'
    end
  end
  Crux::Git::BatchConfig.from_kyaml(body)
end

# Creates a fake checked-out repo (a directory containing a `.git` subdir).
private def make_existing_repo(root : String, name : String) : Nil
  Dir.mkdir_p(File.join(root, name, ".git"))
end

describe Crux::Git::BatchPuller do
  root = ""

  before_each do
    root = File.join(Dir.tempdir, "crux_batch_#{Time.utc.to_unix_ms}_#{rand(10000)}")
    Dir.mkdir_p(root)
  end

  after_each do
    FileUtils.rm_rf(root) if Dir.exists?(root)
  end

  it "clones repositories that are absent locally" do
    git = FakeGit.new
    batch = batch_config(root, [{"git@host:org/newrepo.git", "default"}])

    outcomes = Crux::Git::BatchPuller.new(git, batch, profiles_with_default).run

    outcomes.size.should eq(1)
    outcomes[0].kind.should eq(Crux::Git::RepoOutcome::Kind::Cloned)
    git.called?("clone").should be_true
  end

  it "reports up to date when an existing repo did not move" do
    make_existing_repo(root, "stay")
    git = FakeGit.new
    # rev-parse before and after the pull return the same HEAD.
    git.stub("rev-parse", ok_result("abc123\n"), ok_result("abc123\n"))
    batch = batch_config(root, [{"git@host:org/stay.git", "default"}])

    outcomes = Crux::Git::BatchPuller.new(git, batch, profiles_with_default).run

    outcomes[0].kind.should eq(Crux::Git::RepoOutcome::Kind::UpToDate)
    git.called?("pull").should be_true
    git.called?("clone").should be_false
  end

  it "summarizes updates when an existing repo advances" do
    make_existing_repo(root, "moved")
    git = FakeGit.new
    git.stub("rev-parse", ok_result("aaa\n"), ok_result("bbb\n"))
    git.stub("rev-list", ok_result("3\n"))
    git.stub("diff", ok_result(" 2 files changed, 10 insertions(+), 1 deletion(-)\n"))
    batch = batch_config(root, [{"git@host:org/moved.git", "default"}])

    outcomes = Crux::Git::BatchPuller.new(git, batch, profiles_with_default).run

    outcomes[0].kind.should eq(Crux::Git::RepoOutcome::Kind::Updated)
    outcomes[0].detail.should contain("3 commits")
    outcomes[0].detail.should contain("2 files changed")
  end

  it "marks a repo failed when its profile is unknown" do
    git = FakeGit.new
    batch = batch_config(root, [{"git@host:org/orphan.git", "ghost"}])

    outcomes = Crux::Git::BatchPuller.new(git, batch, profiles_with_default).run

    outcomes[0].kind.should eq(Crux::Git::RepoOutcome::Kind::Failed)
    outcomes[0].detail.should contain("unknown profile")
    git.called?("clone").should be_false
  end

  it "surfaces a clone failure as a Failed outcome" do
    git = FakeGit.new
    git.stub("clone", fail_result("fatal: repository not found\n"))
    batch = batch_config(root, [{"git@host:org/missing.git", "default"}])

    outcomes = Crux::Git::BatchPuller.new(git, batch, profiles_with_default).run

    outcomes[0].kind.should eq(Crux::Git::RepoOutcome::Kind::Failed)
    outcomes[0].detail.should contain("repository not found")
  end

  it "preserves input order across concurrent processing" do
    make_existing_repo(root, "b")
    git = FakeGit.new
    batch = batch_config(root, [
      {"git@host:org/a.git", "default"},
      {"git@host:org/b.git", "default"},
      {"git@host:org/c.git", "default"},
    ])

    outcomes = Crux::Git::BatchPuller.new(git, batch, profiles_with_default).run
    outcomes.map(&.name).should eq(["a", "b", "c"])
  end
end
