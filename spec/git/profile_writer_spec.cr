require "../spec_helper"
require "file_utils"

private def make_profile(name : String = "personal", *, signing : Bool = true) : Crux::Git::Profile
  Crux::Git::Profile.new(
    name: name,
    ssh_key: "/home/dev/.ssh/id_#{name}",
    ssh_host_alias: "github-#{name}",
    signing_key: signing ? "/home/dev/.ssh/id_#{name}.pub" : nil,
    user: Crux::Git::Identity.new("Dev", "dev@example.com"),
  )
end

describe Crux::Git::ProfileWriter do
  tmp = ""
  writer = Crux::Git::ProfileWriter.new

  before_each do
    tmp = File.join(Dir.tempdir, "crux_pw_#{Time.utc.to_unix_ms}_#{rand(10000)}")
    Dir.mkdir_p(tmp)
    writer = Crux::Git::ProfileWriter.new(
      profiles_path: File.join(tmp, "profiles.kyaml"),
      ssh_config_path: File.join(tmp, "ssh_config"),
      fragment_dir: File.join(tmp, "fragments"),
    )
  end

  after_each do
    FileUtils.rm_rf(tmp) if Dir.exists?(tmp)
  end

  describe "#save_profile" do
    it "persists a profile that round-trips through load_profiles" do
      writer.save_profile(make_profile)

      loaded = writer.load_profiles.find("personal")
      loaded.should_not be_nil
      loaded.try(&.ssh_host_alias).should eq("github-personal")
      loaded.try(&.signing_key).should eq("/home/dev/.ssh/id_personal.pub")
      loaded.try(&.user).try(&.email).should eq("dev@example.com")
    end

    it "upserts rather than duplicating a profile of the same name" do
      writer.save_profile(make_profile)
      writer.save_profile(make_profile) # same name again

      writer.load_profiles.profiles.count(&.name.==("personal")).should eq(1)
    end

    it "keeps distinct profiles side by side" do
      writer.save_profile(make_profile("personal"))
      writer.save_profile(make_profile("work"))

      writer.load_profiles.profiles.map(&.name).sort!.should eq(["personal", "work"])
    end
  end

  describe "#append_ssh_config" do
    it "writes the Host block and is idempotent" do
      profile = make_profile
      writer.ssh_alias_present?("github-personal").should be_false

      writer.append_ssh_config(profile, "github.com").should be_true
      writer.ssh_alias_present?("github-personal").should be_true
      writer.append_ssh_config(profile, "github.com").should be_false # no dup

      contents = File.read(writer.ssh_config_path)
      contents.scan(/Host github-personal/).size.should eq(1)
      contents.should contain("IdentityFile /home/dev/.ssh/id_personal")
    end
  end

  describe "#gitconfig_fragment" do
    it "includes ssh signing config when a signing key is set" do
      fragment = writer.gitconfig_fragment(make_profile(signing: true))
      fragment.should contain("signingkey = /home/dev/.ssh/id_personal.pub")
      fragment.should contain("format = ssh")
      fragment.should contain("gpgsign = true")
    end

    it "omits signing config when there is no signing key" do
      fragment = writer.gitconfig_fragment(make_profile(signing: false))
      fragment.should_not contain("format = ssh")
      fragment.should contain("email = dev@example.com")
    end
  end
end
