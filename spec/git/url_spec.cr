require "spec"
require "../../src/git/url"

describe Git::URL do
  describe ".parse" do
    it "parses an ssh:// URL with user, host, port and path" do
      url = Git::URL.parse("ssh://git@example.com:2222/team/repo.git")
      url.user.should eq("git")
      url.host.should eq("example.com")
      url.port.should eq(2222)
      url.path.should eq("/team/repo.git")
    end

    it "parses an ssh:// URL without a user or port" do
      url = Git::URL.parse("ssh://example.com/repo.git")
      url.user.should be_nil
      url.host.should eq("example.com")
      url.port.should be_nil
      url.path.should eq("/repo.git")
    end

    it "accepts the git+ssh:// scheme alias" do
      url = Git::URL.parse("git+ssh://git@host/x.git")
      url.host.should eq("host")
      url.path.should eq("/x.git")
    end

    it "parses an scp-like remote" do
      url = Git::URL.parse("git@github.com:owner/repo.git")
      url.user.should eq("git")
      url.host.should eq("github.com")
      url.port.should be_nil
      url.path.should eq("owner/repo.git")
    end

    it "parses an scp-like remote with an absolute path" do
      url = Git::URL.parse("git@host:/srv/git/repo.git")
      url.path.should eq("/srv/git/repo.git")
    end

    it "parses a bracketed IPv6 host with a port" do
      url = Git::URL.parse("ssh://git@[::1]:22/repo.git")
      url.host.should eq("::1")
      url.port.should eq(22)
      url.path.should eq("/repo.git")
    end

    it "builds the ssh destination token" do
      Git::URL.parse("ssh://git@host/r").ssh_destination.should eq("git@host")
      Git::URL.parse("ssh://host/r").ssh_destination.should eq("host")
    end

    it "rejects a local-looking path" do
      expect_raises(Git::InvalidURLError) { Git::URL.parse("./some/dir") }
    end

    it "rejects an empty URL" do
      expect_raises(Git::InvalidURLError) { Git::URL.parse("   ") }
    end

    it "rejects an invalid port" do
      expect_raises(Git::InvalidURLError) { Git::URL.parse("ssh://host:notaport/r") }
    end

    it "rejects an ssh:// URL with no path" do
      expect_raises(Git::InvalidURLError) { Git::URL.parse("ssh://host") }
    end
  end
end
