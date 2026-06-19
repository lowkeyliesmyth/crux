require "../../../spec_helper"
require "../../../support/fake_git"
require "file_utils"

describe Crux::Commands::Pull do
  config_home = ""
  repo_root = ""

  before_each do
    config_home = File.join(Dir.tempdir, "crux_pull_cfg_#{Time.utc.to_unix_ms}_#{rand(10000)}")
    repo_root = File.join(Dir.tempdir, "crux_pull_root_#{Time.utc.to_unix_ms}_#{rand(10000)}")
    Dir.mkdir_p(config_home)
    Dir.mkdir_p(repo_root)
    ENV["CRUX_CONFIG_HOME"] = config_home

    File.write(File.join(config_home, "profiles.kyaml"), "profiles:\n  - name: default\n")
    File.write(File.join(config_home, "batch.kyaml"),
      "root: #{repo_root}\nrepos:\n  - url: git@host:org/fresh.git\n    profile: default\n")
  end

  after_each do
    ENV.delete("CRUX_CONFIG_HOME")
    FileUtils.rm_rf(config_home) if Dir.exists?(config_home)
    FileUtils.rm_rf(repo_root) if Dir.exists?(repo_root)
  end

  it "clones a missing repo and reports the summary" do
    git = FakeGit.new
    cmd = Crux::Commands::Pull.new(git)
    output = IO::Memory.new
    cmd.stdout = output
    cmd.execute([] of String)

    git.called?("clone").should be_true
    output.to_s.should contain("fresh")
    output.to_s.should contain("1 cloned")
  end
end
