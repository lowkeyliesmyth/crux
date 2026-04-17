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

# Created a thin test subclass to expose protected methods and enable testing via spec below
# Why? `protected` methods cannot be called directly from outside the class, so we need a test subclass to expose them and make them testable in specs.
class TestableYsplit < Crux::Commands::Ysplit
  def test_fetch_remote(url : URI, redirects_remaining : Int32 = MAX_REDIRECTS) : String
    fetch_remote(url, redirects_remaining)
  end
end

describe TestableYsplit do
  describe "#fetch_remote" do
    # Still use the `subject` defined in the context
    # Otherwise recreate it if necessary
    subject = TestableYsplit.new

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

        expect_raises(Crux::Commands::Ysplit::YsplitError, /Max redirects exceeded/) do
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
      it "raises YsplitError when response body exceeds MAX_RESPONSE_BYTES (20MB)" do
        oversized = "a" * (Crux::Commands::Ysplit::MAX_RESPONSE_BYTES + 1)
        WebMock.stub(:get, "https://example.com/manifests.yaml")
          .to_return(status: 200, body: oversized)

        expect_raises(Crux::Commands::Ysplit::YsplitError, /Response body exceeds/) do
          subject.test_fetch_remote(URI.parse("https://example.com/manifests.yaml"))
        end
      end
    end

    context "raises on failure cases" do
      it "raises YsplitError on non-2xx/3xx responses" do
        WebMock.stub(:get, "https://example.com/manifests.yaml")
          .to_return(status: 404, body: "Not Found")

        expect_raises(Crux::Commands::Ysplit::YsplitError, /HTTP 404/) do
          subject.test_fetch_remote(URI.parse("https://example.com/manifests.yaml"))
        end
      end

      it "raises YsplitError on network failures" do
        expect_raises(Crux::Commands::Ysplit::YsplitError, /Network error/) do
          subject.test_fetch_remote(URI.parse("https://no-stub-registered.com/manifests.yaml"))
        end
      end
    end
  end
end

describe Crux::Commands::Ysplit do
  subject = Crux::Commands::Ysplit.new

  describe "#validate_yaml_url" do
    context "with valid URLS" do
      it "accepts http:// URL with .yaml extension" do
        url = URI.parse("http://example.com/manifests.yaml")
        result = subject.validate_yaml_url(url)
        result.should be_truthy
      end

      it "accepts https:// URL with .yml extension" do
        url = URI.parse("https://raw.githubusercontent.com/org/repo/branch/deploy.yml")
        result = subject.validate_yaml_url(url)
        result.should be_truthy
      end

      it "accepts case-insensitive .YAML extension" do
        url = URI.parse("http://example.com/manifests.YAML")
        result = subject.validate_yaml_url(url)
        result.should be_truthy
      end
    end

    context "with invalid URLS" do
      it "rejects non http(s):// scheme" do
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
