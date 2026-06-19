require "../../../spec_helper"
require "file_utils"

describe Crux::Commands::ProfileList do
  config_home = ""

  before_each do
    config_home = File.join(Dir.tempdir, "crux_plist_#{Time.utc.to_unix_ms}_#{rand(10000)}")
    Dir.mkdir_p(config_home)
    ENV["CRUX_CONFIG_HOME"] = config_home
  end

  after_each do
    ENV.delete("CRUX_CONFIG_HOME")
    FileUtils.rm_rf(config_home) if Dir.exists?(config_home)
  end

  it "reports when no profiles are configured" do
    cmd = Crux::Commands::ProfileList.new
    output = IO::Memory.new
    cmd.stdout = output
    cmd.execute([] of String)

    output.to_s.should contain("No profiles configured")
  end

  it "lists configured profiles with their fields" do
    File.write(File.join(config_home, "profiles.kyaml"), <<-KYAML)
      profiles:
        - name: personal
          sshHostAlias: github-personal
          sshKey: ~/.ssh/id_personal
        - name: work
          sshHostAlias: github-work
      KYAML

    cmd = Crux::Commands::ProfileList.new
    output = IO::Memory.new
    cmd.stdout = output
    cmd.execute([] of String)

    text = output.to_s
    text.should contain("2 profiles")
    text.should contain("personal")
    text.should contain("github-personal")
    text.should contain("work")
  end
end
