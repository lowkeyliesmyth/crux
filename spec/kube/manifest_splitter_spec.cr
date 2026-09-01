require "../spec_helper"
require "../support/kube_manifest_fixtures"

describe Crux::Kube::ManifestSplitter do
  describe "#build_filename" do
    it "produces <outdir>/<name>-<kind>.yaml without a prefix" do
      processor = Crux::Kube::ManifestSplitter.new("/tmp/out")
      result = processor.build_filename("my-app", "deployment")
      result.should eq Path.new("/tmp/out", "my-app-deployment.yaml")
    end

    it "produces <outdir>/<prefix>-<name>-<kind>.yaml with a prefix" do
      processor = Crux::Kube::ManifestSplitter.new("/tmp/out", "myprefix")
      result = processor.build_filename("my-app", "deployment")
      result.should eq Path.new("/tmp/out", "myprefix-my-app-deployment.yaml")
    end

    it "downcases the filename when no prefix is provided" do
      processor = Crux::Kube::ManifestSplitter.new("/tmp/out")
      result = processor.build_filename("My-App", "deployment")
      result.should eq Path.new("/tmp/out", "my-app-deployment.yaml")
    end

    it "respects user-provided casing for filename prefix" do
      processor = Crux::Kube::ManifestSplitter.new("/tmp/out", "MyPrefix")
      result = processor.build_filename("my-app", "deployment")
      result.should eq Path.new("/tmp/out", "MyPrefix-my-app-deployment.yaml")
    end
  end

  describe "#process" do
    temp_dir = ""
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    before_each do
      temp_dir = File.join(Dir.tempdir, "splitter_spec_#{Time.utc.to_unix_ms}")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
    end

    after_each do
      File.chmod(temp_dir, 0o755) if Dir.exists?(temp_dir)
      FileUtils.rm_rf(temp_dir)
    end

    context "with valid YAML" do
      it "writes a single doc and returns 'written: 1, skipped: 0'" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::VALID_SINGLE_DOC, out_io, err_io)
        result.should eq({written: 1, skipped: 0})
        File.exists?(Path.new(temp_dir, "my-app-deployment.yaml")).should be_true
      end

      it "writes one file per doc for multi-doc YAML" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::VALID_MULTI_DOC, out_io, err_io)
        result[:written].should eq(2)
        result[:skipped].should eq(0)
        File.exists?(Path.new(temp_dir, "my-app-deployment.yaml")).should be_true
        File.exists?(Path.new(temp_dir, "my-app-service.yaml")).should be_true
      end

      it "writes correct YAML content into the output file" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        processor.process(KubeManifestFixtures::VALID_SINGLE_DOC, out_io, err_io)
        content = File.read(Path.new(temp_dir, "my-app-deployment.yaml"))
        content.should contain("apiVersion: apps/v1")
        content.should contain("kind: Deployment")
        content.should contain("name: my-app")
      end

      it "writes confirmation line to out_io for each file written" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        processor.process(KubeManifestFixtures::VALID_SINGLE_DOC, out_io, err_io)
        out_io.to_s.should contain("Written:")
      end
      it "applies the prefix to output filenames" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir, "FOO")
        processor.process(KubeManifestFixtures::VALID_SINGLE_DOC, out_io, err_io)
        File.exists?(Path.new(temp_dir, "FOO-my-app-deployment.yaml")).should be_true
      end
    end

    context "with ConfigMap data normalization" do
      it "writes ConfigMap multiline data as a literal block scalar" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::CONFIGMAP_MULTILINE_DOC, out_io, err_io)

        result.should eq({written: 1, skipped: 0})
        content = File.read(Path.new(temp_dir, "shield-cluster-configmap.yaml"))
        content.should contain("cluster-shield.yaml: |")
        content.should contain("cluster_config:")
        content.should_not contain("\\n")
      end

      it "leaves non-ConfigMap output unchanged from stdlib to_yaml" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        processor.process(KubeManifestFixtures::VALID_SINGLE_DOC, out_io, err_io)

        content = File.read(Path.new(temp_dir, "my-app-deployment.yaml"))
        content.should eq(YAML.parse(KubeManifestFixtures::VALID_SINGLE_DOC).to_yaml)
      end
    end

    context "with edge-case YAML and input" do
      it "silently skips bare --- separators" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process("---\n---\n---", out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(0)
      end
      it "returns 'written: 0, skipped: 0' for empty input" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process("", out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(0)
      end
      it "writes valid docs and skips invalid ones" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::MIXED_DOC, out_io, err_io)
        result[:written].should eq(1)
        result[:skipped].should eq(1)
      end
    end

    context "with invalid YAML" do
      it "skips doc missing 'kind' and emits warning to err_io" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::MISSING_KIND_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("Missing required")
      end
      it "skips doc missing 'metadata.name' and emits warning to err_io" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::MISSING_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("Missing required")
      end
      it "skips doc with null name and emits warning to err_io" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::NULL_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("Missing required")
      end
      it "raises YAML::ParseException for malformed YAML input" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        expect_raises(YAML::ParseException) do
          processor.process(KubeManifestFixtures::MALFORMED_YAML, out_io, err_io)
        end
      end
    end

    context "with unsafe metadata.name" do
      it "skips a doc whose name contains '..' and writes nothing" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::TRAVERSAL_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
        File.exists?(Path.new("/tmp", "pwned-configmap.yaml")).should be_false
      end

      it "skips a doc whose name contains '/'" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::SLASH_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "skips a doc whose name contains '\\'" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::BACKSLASH_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "skips a doc whose name contains Unicode NULL byte" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::NULL_UNI_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "skips a doc whose name has a leading dot" do
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::LEADING_DOT_NAME_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "skips a doc whose name exceeds 253 chars" do
        overlong = "a" * (Crux::Kube::ManifestSplitter::RFC_1123_MAX_LENGTH + 1)
        yaml = "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: #{overlong}\n"
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(yaml, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("invalid 'metadata.name'")
      end

      it "still accepts RFC-1123 compliant names" do
        yaml = <<-YML
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: my.app-1.example.net.com
          YML
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(yaml, out_io, err_io)
        result[:written].should eq(1)
        result[:skipped].should eq(0)
        err_io.to_s.should be_empty
      end
    end

    context "when output dir is not writable" do
      it "counts doc as skipped and emits warning to err_io" do
        Dir.mkdir_p(temp_dir, 555)
        processor = Crux::Kube::ManifestSplitter.new(temp_dir)
        result = processor.process(KubeManifestFixtures::VALID_SINGLE_DOC, out_io, err_io)
        result[:written].should eq(0)
        result[:skipped].should eq(1)
        err_io.to_s.should contain("Failed to write")
      end
    end

    it "skips a doc when the prefixed path resolves outside outdir" do
      escaped_name = "manifest-splitter-outside-#{Time.utc.to_unix_ms}"
      escaped_path = File.join(Dir.tempdir, "#{escaped_name}-my-app-deployment.yaml")

      begin
        processor = Crux::Kube::ManifestSplitter.new(temp_dir, "../#{escaped_name}")
        result = processor.process(KubeManifestFixtures::VALID_SINGLE_DOC, out_io, err_io)

        result.should eq({written: 0, skipped: 1})
        err_io.to_s.should contain("outside outdir")
        File.exists?(escaped_path).should be_false
      ensure
        File.delete(escaped_path) if File.exists?(escaped_path)
      end
    end
  end
end
