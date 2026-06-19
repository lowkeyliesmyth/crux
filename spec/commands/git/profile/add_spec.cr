require "../../../spec_helper"
require "../../../support/fake_keygen"
require "file_utils"

describe Crux::Commands::ProfileAdd do
  tmp = ""

  before_each do
    tmp = File.join(Dir.tempdir, "crux_padd_#{Time.utc.to_unix_ms}_#{rand(10000)}")
    Dir.mkdir_p(tmp)
  end

  after_each do
    FileUtils.rm_rf(tmp) if Dir.exists?(tmp)
  end

  it "generates a key, wires ssh/git config, and saves the profile" do
    keygen = FakeKeyGen.new
    writer = Crux::Git::ProfileWriter.new(
      profiles_path: File.join(tmp, "profiles.kyaml"),
      ssh_config_path: File.join(tmp, "ssh_config"),
      fragment_dir: File.join(tmp, "fragments"),
    )
    key_path = File.join(tmp, "keys", "id_personal")

    # name, host(default), alias(default), key path, commit name, commit email,
    # signing(default yes), apply(default yes)
    script = "personal\n\n\n#{key_path}\nDev\ndev@example.com\n\n\n"

    cmd = Crux::Commands::ProfileAdd.new(keygen, writer)
    cmd.stdin = IO::Memory.new(script)
    output = IO::Memory.new
    cmd.stdout = output
    cmd.execute([] of String)

    # key generated
    keygen.generated.size.should eq(1)
    File.exists?(key_path).should be_true
    File.exists?("#{key_path}.pub").should be_true

    # ssh config wired
    File.read(writer.ssh_config_path).should contain("Host github-personal")

    # gitconfig fragment written
    File.read(writer.fragment_path("personal")).should contain("format = ssh")

    # profile saved and round-trips
    saved = writer.load_profiles.find("personal")
    saved.should_not be_nil
    saved.try(&.ssh_host_alias).should eq("github-personal")
    output.to_s.should contain("Saved profile")
  end

  it "reuses an existing key instead of regenerating" do
    keygen = FakeKeyGen.new
    writer = Crux::Git::ProfileWriter.new(
      profiles_path: File.join(tmp, "profiles.kyaml"),
      ssh_config_path: File.join(tmp, "ssh_config"),
      fragment_dir: File.join(tmp, "fragments"),
    )
    key_path = File.join(tmp, "id_existing")
    File.write(key_path, "already here\n")

    script = "personal\n\n\n#{key_path}\n\n\n\n\n"
    cmd = Crux::Commands::ProfileAdd.new(keygen, writer)
    cmd.stdin = IO::Memory.new(script)
    output = IO::Memory.new
    cmd.stdout = output
    cmd.execute([] of String)

    keygen.generated.should be_empty
    output.to_s.should contain("Reusing existing key")
    writer.load_profiles.find("personal").should_not be_nil
  end

  it "aborts without writing anything when the user declines" do
    keygen = FakeKeyGen.new
    writer = Crux::Git::ProfileWriter.new(
      profiles_path: File.join(tmp, "profiles.kyaml"),
      ssh_config_path: File.join(tmp, "ssh_config"),
      fragment_dir: File.join(tmp, "fragments"),
    )
    key_path = File.join(tmp, "keys", "id_personal")

    # ...same prompts but decline the final apply
    script = "personal\n\n\n#{key_path}\nDev\ndev@example.com\n\nn\n"
    cmd = Crux::Commands::ProfileAdd.new(keygen, writer)
    cmd.stdin = IO::Memory.new(script)
    output = IO::Memory.new
    cmd.stdout = output
    cmd.execute([] of String)

    keygen.generated.should be_empty
    File.exists?(writer.profiles_path).should be_false
    output.to_s.should contain("Aborted")
  end
end
