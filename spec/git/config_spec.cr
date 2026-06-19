require "../spec_helper"
require "file_utils"

# Writes `content` to a uniquely named temp file with `suffix` and returns the path.
private def write_temp(content : String, suffix : String) : String
  path = File.join(Dir.tempdir, "crux_git_cfg_#{Time.utc.to_unix_ms}_#{rand(10000)}#{suffix}")
  File.write(path, content)
  path
end

PROFILES_KYAML = <<-KYAML
  profiles:
    - name: personal
      sshKey: ~/.ssh/id_personal
      sshHostAlias: github-personal
      user:
        name: Lowkey
        email: lowkey@example.com
    - name: work
      signingKey: ABC123
  KYAML

BATCH_KYAML = <<-KYAML
  root: /tmp/src
  repos:
    - url: git@github-personal:lowkey/crux.git
      profile: personal
    - url: https://github.com/foo/bar.git
      profile: work
      path: custom-bar
  KYAML

describe Crux::Git::ProfilesConfig do
  it "loads profiles and finds by name" do
    path = write_temp(PROFILES_KYAML, ".kyaml")
    config = Crux::Git::ProfilesConfig.load(path)

    config.profiles.size.should eq(2)
    # ameba:disable Lint/NotNil
    config.find("personal").not_nil!.ssh_host_alias.should eq("github-personal")
    # ameba:disable Lint/NotNil
    config.find("work").not_nil!.signing_key.should eq("ABC123")
    config.find("missing").should be_nil
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  it "raises ConfigError when the file is missing" do
    expect_raises(Crux::Git::ConfigError, /not found/) do
      Crux::Git::ProfilesConfig.load("/nonexistent/profiles.kyaml")
    end
  end
end

describe Crux::Git::Profile do
  it "builds a GIT_SSH_COMMAND env when an ssh key is set" do
    path = write_temp(PROFILES_KYAML, ".kyaml")
    # ameba:disable Lint/NotNil
    profile = Crux::Git::ProfilesConfig.load(path).find("personal").not_nil!

    # ameba:disable Lint/NotNil
    env = profile.git_env.not_nil!
    env["GIT_SSH_COMMAND"].should contain("ssh -i ")
    env["GIT_SSH_COMMAND"].should contain("IdentitiesOnly=yes")
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  it "returns nil env when no ssh key is set" do
    path = write_temp(PROFILES_KYAML, ".kyaml")
    # ameba:disable Lint/NotNil
    profile = Crux::Git::ProfilesConfig.load(path).find("work").not_nil!
    profile.git_env.should be_nil
  ensure
    File.delete(path) if path && File.exists?(path)
  end
end

describe Crux::Git::BatchConfig do
  it "loads repos and derives directory names" do
    path = write_temp(BATCH_KYAML, ".kyaml")
    config = Crux::Git::BatchConfig.load(path)

    config.repos.size.should eq(2)
    config.repos[0].dir_name.should eq("crux")
    config.repos[1].dir_name.should eq("custom-bar")
  ensure
    File.delete(path) if path && File.exists?(path)
  end
end

describe Crux::Git::CommitConfig do
  it "returns permissive defaults when no file exists" do
    dir = File.join(Dir.tempdir, "crux_no_config_#{Time.utc.to_unix_ms}")
    Dir.mkdir_p(dir)
    config = Crux::Git::CommitConfig.load(dir)

    config.ticket_required?.should be_false
    config.allowed_types.should eq(Crux::Git::ConventionalCommit::DEFAULT_TYPES)
  ensure
    FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
  end

  it "loads a ticket policy and type overrides from .crux.kyaml" do
    dir = File.join(Dir.tempdir, "crux_with_config_#{Time.utc.to_unix_ms}")
    Dir.mkdir_p(dir)
    File.write(File.join(dir, Crux::Git::CommitConfig::FILE_NAME), <<-KYAML)
      ticket:
        required: true
        pattern: "[A-Z]+-\\\\d+"
      types:
        - feat
        - fix
      KYAML

    config = Crux::Git::CommitConfig.load(dir)
    config.ticket_required?.should be_true
    config.allowed_types.should eq(["feat", "fix"])
    # ameba:disable Lint/NotNil
    config.ticket.not_nil!.valid?("JIRA-123").should be_true
    # ameba:disable Lint/NotNil
    config.ticket.not_nil!.valid?("nope").should be_false
  ensure
    FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
  end
end
