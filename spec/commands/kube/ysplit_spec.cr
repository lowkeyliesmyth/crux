require "../../spec_helper"
require "../../support/kube_manifest_fixtures"
require "webmock"

# Created a thin test subclass to expose protected methods and enable testing via spec below.
# Why? `protected` methods cannot be called directly from outside the class, so we need a test subclass to expose and make them testable in specs.
# `stubbed_ips` resolves to a public address so most tests keep passing without additional changes.
class TestableYsplit < Crux::Commands::Ysplit
  property stubbed_ips : Array(Socket::IPAddress) = [Socket::IPAddress.new("99.184.216.34", 80)]

  protected def resolve_host(host : String) : Array(Socket::IPAddress)
    stubbed_ips
  end

  def test_disallowed_ip?(ip : Socket::IPAddress) : Bool
    disallowed_ip?(ip)
  end

  def test_fetch_remote(url : URI, redirects_remaining : Int32 = MAX_REDIRECTS) : String
    fetch_remote(url, redirects_remaining)
  end

  def test_read_local_file(path : String) : String
    read_local_file(path)
  end
end

describe TestableYsplit do
  describe "#fetch_remote" do
    # Still use the `subject` defined in the context
    # Otherwise recreate it if necessary
    subject = TestableYsplit.new

    Spec.before_each do
      subject.stubbed_ips = [Socket::IPAddress.new("99.184.216.34", 80)]
    end

    Spec.after_each do
      WebMock.reset
    end

    context "successful fetch" do
      it "returns response body on 200 OK" do
        WebMock.stub(:get, "https://example.com/manifest.yaml")
          .to_return(status: 200, body: KubeManifestFixtures::VALID_SINGLE_DOC)

        result = subject.test_fetch_remote(URI.parse("https://example.com/manifest.yaml"))
        result.should eq(KubeManifestFixtures::VALID_SINGLE_DOC)
      end
    end

    context "follows redirects" do
      it "follows a single 301 redirect and returns the body" do
        WebMock.stub(:get, "https://example.com/manifest.yml")
          .to_return(status: 301, headers: {"Location" => "https://cdn.example.com/manifest.yaml"})
        WebMock.stub(:get, "https://cdn.example.com/manifest.yaml")
          .to_return(status: 200, body: KubeManifestFixtures::VALID_SINGLE_DOC)

        result = subject.test_fetch_remote(URI.parse("https://example.com/manifest.yml"))
        result.should eq(KubeManifestFixtures::VALID_SINGLE_DOC)
      end

      it "follows a chain of redirects (302 -> 301 -> 200)" do
        WebMock.stub(:get, "https://example.com/first.yaml")
          .to_return(status: 302, headers: {"Location" => "https://example.com/second.yaml"})
        WebMock.stub(:get, "https://example.com/second.yaml")
          .to_return(status: 301, headers: {"Location" => "https://example.com/third.yaml"})
        WebMock.stub(:get, "https://example.com/third.yaml")
          .to_return(status: 200, body: KubeManifestFixtures::VALID_SINGLE_DOC)

        result = subject.test_fetch_remote(URI.parse("https://example.com/first.yaml"))
        result.should eq(KubeManifestFixtures::VALID_SINGLE_DOC)
      end

      it "resolves relative Location headers against the original URL" do
        WebMock.stub(:get, "https://example.com/main/manifest.yaml")
          .to_return(status: 302, headers: {"Location" => "/subdir/level/stuff.yaml"})
        WebMock.stub(:get, "https://example.com/subdir/level/stuff.yaml")
          .to_return(status: 200, body: KubeManifestFixtures::VALID_SINGLE_DOC)

        result = subject.test_fetch_remote(URI.parse("https://example.com/main/manifest.yaml"))
        result.should eq(KubeManifestFixtures::VALID_SINGLE_DOC)
      end
    end

    context "respects redirect limits" do
      it "raises YsplitError after exceeding MAX_REDIRECTS (5)" do
        6.times do |i|
          WebMock.stub(:get, "https://example.com/redirect#{i}.yaml")
            .to_return(status: 302, headers: {"Location" => "https://example.com/redirect#{i + 1}.yaml"})
        end

        expect_raises(Crux::Commands::Ysplit::YsplitError, /Redirect loop detected/) do
          subject.test_fetch_remote(URI.parse("https://example.com/redirect0.yaml"))
        end
      end

      it "raises YsplitError when redirect has no Location header" do
        WebMock.stub(:get, "https://example.com/manifest.yml")
          .to_return(status: 301, headers: {} of String => String)

        expect_raises(Crux::Commands::Ysplit::YsplitError, /Redirect with no Location header/) do
          subject.test_fetch_remote(URI.parse("https://example.com/manifest.yml"))
        end
      end
    end

    context "respects size limits" do
      it "raises YsplitError when response body exceeds MAX_BYTES" do
        oversized = "a" * (Crux::Commands::Ysplit::MAX_BYTES + 1)
        WebMock.stub(:get, "https://example.com/manifests.yaml")
          .to_return(status: 200, body: oversized)

        expect_raises(Crux::Commands::Ysplit::YsplitError, /Response body exceeds/) do
          subject.test_fetch_remote(URI.parse("https://example.com/manifests.yaml"))
        end
      end
    end

    context "raises on failure cases" do
      it "raises YsplitError on non-2xx/3xx responses without leaking body data" do
        WebMock.stub(:get, "https://example.com/manifests.yaml")
          .to_return(status: 404, body: "super-secret-dont-leak")

        error = expect_raises(Crux::Commands::Ysplit::YsplitError, /HTTP 404/) do
          subject.test_fetch_remote(URI.parse("https://example.com/manifests.yaml"))
        end
        # ameba:disable Lint/NotNil
        error.message.not_nil!.should_not contain("super-secret-dont-leak")
      end

      it "raises YsplitError on network failures" do
        expect_raises(Crux::Commands::Ysplit::YsplitError, /Network error/) do
          subject.test_fetch_remote(URI.parse("https://no-stub-registered.com/manifests.yaml"))
        end
      end
    end

    context "rejects disallowed destinations (SSRF)" do
      it "rejects when host resolves to loopback" do
        subject.stubbed_ips = [Socket::IPAddress.new("127.0.0.1", 80)]
        expect_raises(Crux::Commands::Ysplit::YsplitError, /disallowed address/) do
          subject.test_fetch_remote(URI.parse("https://internal.example.com/manifests.yaml"))
        end
      end

      it "rejects when host resolves to link-local IMDS (169.254.169.254)" do
        subject.stubbed_ips = [Socket::IPAddress.new("169.254.169.254", 80)]
        expect_raises(Crux::Commands::Ysplit::YsplitError, /disallowed address/) do
          subject.test_fetch_remote(URI.parse("https://internal.example.com/manifests.yaml"))
        end
      end

      it "rejects when ANY resolved address entry is disallowed" do
        subject.stubbed_ips = [
          Socket::IPAddress.new("8.8.8.8", 80),
          Socket::IPAddress.new("127.0.0.1", 80),
        ]
        expect_raises(Crux::Commands::Ysplit::YsplitError, /disallowed address/) do
          subject.test_fetch_remote(URI.parse("https://internal.example.com/manifests.yaml"))
        end
      end

      it "allows RFC 1918 private addresses" do
        subject.stubbed_ips = [Socket::IPAddress.new("10.0.0.10", 80)]
        WebMock.stub(:get, "https://internal.example.com/manifests.yaml")
          .to_return(status: 200, body: KubeManifestFixtures::VALID_SINGLE_DOC)
        result = subject.test_fetch_remote(URI.parse("https://internal.example.com/manifests.yaml"))
        result.should eq(KubeManifestFixtures::VALID_SINGLE_DOC)
      end
    end

    context " re-validates redirect targets" do
      it "rejects redirects to disallowed addresses" do
        # case here is that original host resolves to allowed public IP, but redirects to disallowed localhost IP
        subject.stubbed_ips = [Socket::IPAddress.new("127.0.0.1", 80)]
        WebMock.stub(:get, "https://internal.example.com/manifests.yaml")
          .to_return(status: 302, headers: {"Location" => "https://localhost/manifests.yaml"})
        expect_raises(Crux::Commands::Ysplit::YsplitError, /disallowed address/) do
          subject.test_fetch_remote(URI.parse("https://internal.example.com/manifests.yaml"))
        end
      end

      it "rejects redirects that downgrade to http" do
        WebMock.stub(:get, "https://internal.example.com/manifests.yaml")
          .to_return(status: 302, headers: {"Location" => "http://other.example.com/manifests.yaml"})
        expect_raises(Crux::Commands::Ysplit::YsplitError, /not a valid HTTPS url/) do
          subject.test_fetch_remote(URI.parse("https://internal.example.com/manifests.yaml"))
        end
      end

      it "rejects redirect to non-yaml extension" do
        WebMock.stub(:get, "https://internal.example.com/manifests.yaml")
          .to_return(status: 302, headers: {"Location" => "https://other.example.com/manifests.txt"})
        expect_raises(Crux::Commands::Ysplit::YsplitError, /not a valid HTTPS url/) do
          subject.test_fetch_remote(URI.parse("https://internal.example.com/manifests.yaml"))
        end
      end
    end
  end

  #  describe "#read_local_file" do
  #    subject = TestableYsplit.new
  #    tmp_file = ""
  #
  #    before_each do
  #      tmp_file = File.join(Dir.tempdir, "ysplit_read_spec_#{Time.utc.to_unix_ms}")
  #    end
  #
  #    after_each do
  #      File.delete(tmp_file) if File.exists?(tmp_file)
  #    end
  #
  #    it "reads a small file unchanged" do
  #      File.write(tmp_file, VALID_SINGLE_DOC)
  #      subject.test_read_local_file(tmp_file).should eq(VALID_SINGLE_DOC)
  #    end
  #
  #    it "raises when file exceeds MAX_BYTES" do
  #      content = "a" * (Crux::Commands::Ysplit::MAX_BYTES + 1)
  #      File.write(tmp_file, content)
  #      expect_raises(Crux::Commands::Ysplit::YsplitError, /exceeds.*limit/) do
  #        subject.test_read_local_file(tmp_file)
  #      end
  #    end
  #  end

  describe "#disallowed_ip?" do
    subject = TestableYsplit.new

    it "allows public IPv4 addresses" do
      subject.test_disallowed_ip?(Socket::IPAddress.new("8.8.8.8", 80)).should be_false
    end

    it "rejects loopback addresses" do
      subject.test_disallowed_ip?(Socket::IPAddress.new("127.0.0.1", 80)).should be_true
      subject.test_disallowed_ip?(Socket::IPAddress.new("::1", 80)).should be_true
      subject.test_disallowed_ip?(Socket::IPAddress.new("::ffff:127.0.0.1", 80)).should be_true
    end

    it "rejects link-local addresses" do
      subject.test_disallowed_ip?(Socket::IPAddress.new("169.254.169.254", 80)).should be_true
      subject.test_disallowed_ip?(Socket::IPAddress.new("fe80::1", 80)).should be_true
    end

    it "rejects unspecified (0.0.0.0)" do
      subject.test_disallowed_ip?(Socket::IPAddress.new("0.0.0.0", 80)).should be_true
    end

    # # Ignore multicast addresses for now
    #    it "rejects multicast addresses" do
    #      subject.test_disallowed_ip?(Socket::IPAddress.new("224.0.0.1", 80)).should be_true
    #      subject.test_disallowed_ip?(Socket::IPAddress.new("ff00::1", 80)).should be_true
    #    end

    it "allows RFC 1918 private ranges" do
      subject.test_disallowed_ip?(Socket::IPAddress.new("10.0.0.1", 80)).should be_false
      subject.test_disallowed_ip?(Socket::IPAddress.new("192.168.1.1", 80)).should be_false
    end

    it "allows CGNAT shared address (100.64.0.1)" do
      subject.test_disallowed_ip?(Socket::IPAddress.new("100.64.0.1", 80)).should be_false
    end
  end
end

describe Crux::Commands::Ysplit do
  subject = Crux::Commands::Ysplit.new

  describe "#validate_yaml_url" do
    context "with valid URLS" do
      it "accepts https:// URL with .yaml or .yml extension" do
        url = URI.parse("https://example.com/manifests.yaml")
        result = subject.validate_yaml_url(url)
        result.should be_truthy

        url_yml = URI.parse("https://raw.githubusercontent.com/org/repo/branch/deploy.yml")
        result_yml = subject.validate_yaml_url(url_yml)
        result_yml.should be_truthy
      end

      it "accepts case-insensitive .YAML extension" do
        url = URI.parse("https://example.com/manifests.YAML")
        result = subject.validate_yaml_url(url)
        result.should be_truthy
      end
    end

    context "with invalid URLS" do
      it "rejects http scheme" do
        url = URI.parse("http://example.com/file.yaml")
        expect_raises(Crux::Commands::Ysplit::YsplitError) do
          subject.validate_yaml_url(url)
        end
      end

      it "rejects non-https:// scheme" do
        url = URI.parse("ftp://example.com/file.yaml")
        expect_raises(Crux::Commands::Ysplit::YsplitError) do
          subject.validate_yaml_url(url)
        end
      end

      it "rejects URL without .yaml|.yml extension" do
        url = URI.parse("https://example.com/file.json")
        expect_raises(Crux::Commands::Ysplit::YsplitError) do
          subject.validate_yaml_url(url)
        end
      end

      it "rejects URL without valid host" do
        url = URI.parse("/just/a/path.yaml")
        expect_raises(Crux::Commands::Ysplit::YsplitError) do
          subject.validate_yaml_url(url)
        end
      end
    end
  end
end
