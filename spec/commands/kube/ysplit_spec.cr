require "../../spec_helper"
require "webmock"

# Fixture YAML doc strings shared across multiple specs
VALID_SINGLE_DOC = <<-YAML
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: my-app
  YAML

VALID_MULTI_DOC = <<-YAML
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: my-app
  ---
  apiVersion: v1
  kind: Service
  metadata:
    name: my-app
  YAML

MISSING_METADATA_DOC = <<-YAML
  apiVersion: apps/v1
  kind: Deployment
  YAML

MISSING_KIND_DOC = <<-YAML
  apiVersion: apps/v1
  metadata:
    name: orphan
  YAML

MISSING_NAME_DOC = <<-YAML
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    namespace: default
  YAML

NULL_NAME_DOC = <<-YAML
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name:
  YAML

TRAVERSAL_NAME_DOC = <<-YAML
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: ../../../tmp/pwned
  YAML

SLASH_NAME_DOC = <<-YAML
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: foo/bar
  YAML

BACKSLASH_NAME_DOC = <<-YAML
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: "foo\\\\bar"
  YAML

NUL_NAME_DOC = <<-YAML
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: "foo\\u0000bar"
  YAML

LEADING_DOT_NAME_DOC = <<-YAML
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: .hidden
  YAML

# One valid doc, one malformed doc
MIXED_DOC = <<-YAML
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: my-app
  ---
  apiVersion: v1
  metadata:
    name: my-app
  YAML

MALFORMED_YAML = <<-YAML
  key: [unclosed bracket
  YAML

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
          .to_return(status: 200, body: VALID_SINGLE_DOC)

        result = subject.test_fetch_remote(URI.parse("https://example.com/manifest.yaml"))
        result.should eq(VALID_SINGLE_DOC)
      end
    end

    context "follows redirects" do
      it "follows a single 301 redirect and returns the body" do
        WebMock.stub(:get, "https://example.com/manifest.yml")
          .to_return(status: 301, headers: {"Location" => "https://cdn.example.com/manifest.yaml"})
        WebMock.stub(:get, "https://cdn.example.com/manifest.yaml")
          .to_return(status: 200, body: VALID_SINGLE_DOC)

        result = subject.test_fetch_remote(URI.parse("https://example.com/manifest.yml"))
        result.should eq(VALID_SINGLE_DOC)
      end

      it "follows a chain of redirects (302 -> 301 -> 200)" do
        WebMock.stub(:get, "https://example.com/first.yaml")
          .to_return(status: 302, headers: {"Location" => "https://example.com/second.yaml"})
        WebMock.stub(:get, "https://example.com/second.yaml")
          .to_return(status: 301, headers: {"Location" => "https://example.com/third.yaml"})
        WebMock.stub(:get, "https://example.com/third.yaml")
          .to_return(status: 200, body: VALID_SINGLE_DOC)

        result = subject.test_fetch_remote(URI.parse("https://example.com/first.yaml"))
        result.should eq(VALID_SINGLE_DOC)
      end

      it "resolves relative Location headers against the original URL" do
        WebMock.stub(:get, "https://example.com/main/manifest.yaml")
          .to_return(status: 302, headers: {"Location" => "/subdir/level/stuff.yaml"})
        WebMock.stub(:get, "https://example.com/subdir/level/stuff.yaml")
          .to_return(status: 200, body: VALID_SINGLE_DOC)

        result = subject.test_fetch_remote(URI.parse("https://example.com/main/manifest.yaml"))
        result.should eq(VALID_SINGLE_DOC)
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
          .to_return(status: 200, body: VALID_SINGLE_DOC)
        result = subject.test_fetch_remote(URI.parse("https://internal.example.com/manifests.yaml"))
        result.should eq(VALID_SINGLE_DOC)
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
        result_yml = subject.validate_yaml_url(url)
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

describe Crux::Commands::Ysplit::K8sDoc do
  describe "#valid?" do
    it "returns true when apiVersion, kind, metadata.name are present" do
      doc = Crux::Commands::Ysplit::K8sDoc.from_yaml(VALID_SINGLE_DOC)
      doc.valid?.should be_true
    end

    it "returns false when kind is missing" do
      doc = Crux::Commands::Ysplit::K8sDoc.from_yaml(MISSING_KIND_DOC)
      doc.valid?.should be_false
    end

    it "returns false when metadata is missing" do
      doc = Crux::Commands::Ysplit::K8sDoc.from_yaml(MISSING_METADATA_DOC)
      doc.valid?.should be_false
    end

    it "returns false when metadata.name is missing" do
      doc = Crux::Commands::Ysplit::K8sDoc.from_yaml(MISSING_NAME_DOC)
      doc.valid?.should be_false
    end

    it "returns false when metadata.name is null" do
      doc = Crux::Commands::Ysplit::K8sDoc.from_yaml(NULL_NAME_DOC)
      doc.valid?.should be_false
    end

    it "returns false when metadata is missing" do
      doc = Crux::Commands::Ysplit::K8sDoc.from_yaml(MISSING_METADATA_DOC)
      doc.valid?.should be_false
    end
  end
end

describe Crux::Commands::Ysplit::YsplitProcessor do
  describe "#build_filename" do
    it "produces <outdir>/<name>-<kind>.yaml without a prefix" do
      processor = Crux::Commands::Ysplit::YsplitProcessor.new("/tmp/out")
      result = processor.build_filename("my-app", "deployment")
      result.should eq Path.new("/tmp/out", "my-app-deployment.yaml")
    end

    it "produces <outdir>/<prefix>-<name>-<kind>.yaml with a prefix" do
      processor = Crux::Commands::Ysplit::YsplitProcessor.new("/tmp/out", "myprefix")
      result = processor.build_filename("my-app", "deployment")
      result.should eq Path.new("/tmp/out", "myprefix-my-app-deployment.yaml")
    end

    it "downcases the filename when no prefix is provided" do
      processor = Crux::Commands::Ysplit::YsplitProcessor.new("/tmp/out")
      result = processor.build_filename("My-App", "deployment")
      result.should eq Path.new("/tmp/out", "my-app-deployment.yaml")
    end

    it "respects user-provided casing for filename prefix" do
      processor = Crux::Commands::Ysplit::YsplitProcessor.new("/tmp/out", "MyPrefix")
      result = processor.build_filename("my-app", "deployment")
      result.should eq Path.new("/tmp/out", "MyPrefix-my-app-deployment.yaml")
    end
  end

  describe "#process" do
    temp_dir = ""
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    before_each do
      temp_dir = File.join(Dir.tempdir, "ysplit_spec_#{Time.utc.to_unix_ms}")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
    end

    after_each do
      File.chmod(temp_dir, 0o755) if Dir.exists?(temp_dir)
      FileUtils.rm_rf(temp_dir)
    end

    context "with valid YAML" do
      it "writes a single doc and returns 'written: 1, skipped: 0'" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(VALID_SINGLE_DOC, out_io, err_io)
        result.should eq({written: 1, skipped: 0})
        File.exists?(Path.new(temp_dir, "my-app-deployment.yaml")).should be_true
      end

      it "writes one file per doc for multi-doc YAML" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(VALID_MULTI_DOC, out_io, err_io)
        result[:written].should eq(2)
        result[:skipped].should eq(0)
        File.exists?(Path.new(temp_dir, "my-app-deployment.yaml")).should be_true
        File.exists?(Path.new(temp_dir, "my-app-service.yaml")).should be_true
      end

      it "writes correct YAML content into the output file" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        processor.process(VALID_SINGLE_DOC, out_io, err_io)
        content = File.read(Path.new(temp_dir, "my-app-deployment.yaml"))
        content.should contain("apiVersion: apps/v1")
        content.should contain("kind: Deployment")
        content.should contain("name: my-app")
      end

      it "writes confirmation line to out_io for each file written" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        processor.process(VALID_SINGLE_DOC, out_io, err_io)
        out_io.to_s.should contain("Written:")
      end
      it "applies the prefix to output filenames" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir, "FOO")
        processor.process(VALID_SINGLE_DOC, out_io, err_io)
        File.exists?(Path.new(temp_dir, "FOO-my-app-deployment.yaml")).should be_true
      end
    end

    context "with edge-case YAML and input" do
      it "silently skips bare --- separators" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process("---\n---\n---", out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(0)
      end
      it "returns 'written: 0, skipped: 0' for empty input" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process("", out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(0)
      end
      it "writes valid docs and skips invalid ones" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(MIXED_DOC, out_io, err_io)
        result[:written].should eq(1)
        result[:skipped].should eq(1)
      end
    end

    context "with invalid YAML" do
      it "skips doc missing 'kind' and emits warning to err_io" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(MISSING_KIND_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("Missing required")
      end
      it "skips doc missing 'metadata.name' and emits warning to err_io" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(MISSING_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("Missing required")
      end
      it "skips doc with null name and emits warning to err_io" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(NULL_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("Missing required")
      end
      it "raises YAML::ParseException for malformed YAML input" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        expect_raises(YAML::ParseException) do
          processor.process(MALFORMED_YAML, out_io, err_io)
        end
      end
    end

    context "with unsafe metadata.name" do
      it "skips a doc whose name contains '..' and writes nothing" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(TRAVERSAL_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
        File.exists?(Path.new("/tmp", "pwned-configmap.yaml")).should be_false
      end

      it "skips a doc whose name contains '/'" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(SLASH_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "skips a doc whose name contains '\\'" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(BACKSLASH_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "skips a doc whose name contains  NUL byte" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(NUL_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "skips a doc whose name has a leading dot" do
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(LEADING_DOT_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "skips a doc whose name exceeds 253 chars" do
        overlong = "a" * (Crux::Commands::Ysplit::YsplitProcessor::RFC_1123_MAX_LENGTH + 1)
        yaml = "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: #{overlong}\n"
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(yaml, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "still accepts RFC-1123 compliant names" do
        yaml = <<-YAML
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: my.app-1.example.net.com
        YAML
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(yaml, out_io, err_io)
        result[:written].should eq(1)
        result[:skipped].should eq(0)
        err_io.to_s.should be_empty
      end
    end

    context "when output dir is not writable" do
      it "counts doc as skipped and emits warning to err_io" do
        Dir.mkdir_p(temp_dir, 555)
        processor = Crux::Commands::Ysplit::YsplitProcessor.new(temp_dir)
        result = processor.process(VALID_SINGLE_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("Failed to write")
      end
    end
  end
end
