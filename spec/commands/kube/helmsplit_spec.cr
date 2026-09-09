require "../../spec_helper"
require "../../support/kube_manifest_fixtures"
require "file_utils"

# Test subclass wrapping and exposing private methods in Helmsplit
class TestableHelmsplit < Crux::Commands::Helmsplit
  def test_resolve_chart(chart : String) : String
    resolve_chart(chart)
  end

  def test_render_chart(chart : String, version : String?, values : Array(String)) : String
    render_chart(chart, version, values)
  end

  def test_sanitize_rendered(rendered : String) : String
    sanitize_rendered(rendered)
  end

  def test_write_provenance(outdir : String, chart : String, version : String?, values : Array(String), prefix : String?, overrides : String?)
    write_provenance(outdir, chart, version, values, prefix, overrides)
  end
end

# Mock Helm collaborator implementation for testing
class MockHelm < Crux::Commands::Helmsplit::Helm
  # Pre-rendered manifests acting as a standin for a real helm template execution's output.
  property rendered_output : String?
  # Control if this mock simulates a successful binary detection state.
  property? installed : Bool = true
  # Control if this mock should simulate a success or a failure state.
  property? should_fail : Bool = false
  # Capture the structured parameters that are passed into the template method for mock introspection.
  property template_calls = [] of {chart: String, version: String?, values: Array(String)}

  def template(chart : String, version : String?, values : Array(String)) : String
    @template_calls << {chart: chart, version: version, values: values}

    if @should_fail
      raise Crux::Commands::Helmsplit::HelmsplitError.new("helm template failed with exit code 1:\nError: chart not found: bogustown")
    end

    if output = @rendered_output
      return output
    end
    # Simulate the output we were getting from FAKE_HELM_ECHO_ARGS to help with verifying internal state
    String.build do |io|
      io << "ARG: template\n"
      io << "ARG: #{chart}\n"
      io << "ARG: --include-crds\n"
      if version
        io << "ARG: --version\n"
        io << "ARG: #{version}\n"
      end
      values.each do |v|
        io << "ARG: --values=#{v}\n"
      end
    end
  end

  def installed? : Bool
    @installed
  end
end

# Executes helmsplit with the materialized **inputs** (command args and options) the command would be passed at real invocation by the cling wrapper, and an abstract **helm**.
#
# Returns the execution status code and captured stdout/err streams.
private def execute_helmsplit(input : Array(String), helm : Crux::Commands::Helmsplit::Helm) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  command = Crux::Commands::Helmsplit.new(helm)
  command.stdout = output
  command.stderr = errors

  status = command.execute(input)
  {status, output.to_s, errors.to_s}
end

describe Crux::Commands::Helmsplit do
  describe "#resolve_chart", tags: "io" do
    subject = TestableHelmsplit.new
    workdir = ""

    before_each do
      workdir = File.join(Dir.tempdir, "helmsplit_resolve_spec_#{Time.utc.to_unix_ms}")
      Dir.mkdir_p(workdir)
    end

    after_each do
      FileUtils.rm_rf(workdir) if Dir.exists?(workdir)
    end

    context "with a valid local chart directory" do
      it "returns the expanded absolute path" do
        File.write(File.join(workdir, "Chart.yaml"), "name: fake\nversion:  0.0.1\n")
        subject.test_resolve_chart(workdir).should eq(File.expand_path(workdir))
      end
    end

    context "with a local dir missing a Chart.yaml" do
      it "raises HelmsplitError calling out Chart.yaml requirement" do
        expect_raises(Crux::Commands::Helmsplit::HelmsplitError, /Missing Chart.yaml/) do
          subject.test_resolve_chart(workdir)
        end
      end
    end

    context "with a local-looking path that doesn't exist" do
      it "raises HelmsplitError for a './' prefix" do
        expect_raises(Crux::Commands::Helmsplit::HelmsplitError, /path not found/) do
          subject.test_resolve_chart("./definitely-missing-#{Time.utc.to_unix_ms}")
        end
      end
    end

    context "with a non-local 'repo/chart' reference" do
      it "returns the original reference unchanged" do
        subject.test_resolve_chart("helm_repo/helm_chart").should eq("helm_repo/helm_chart")
      end
    end
  end

  describe "#render_chart" do
    subject = TestableHelmsplit.new

    context "on successful call" do
      it "returns helm's stdout based on mock" do
        mock_helm = MockHelm.new
        subject = TestableHelmsplit.new(helm: mock_helm)
        result = subject.test_render_chart("jetstack/cert-manager", nil, [] of String)

        # verify the mock was called with the correct arguments
        mock_helm.template_calls.size.should eq(1)
        call = mock_helm.template_calls.first
        call[:chart].should eq("jetstack/cert-manager")
        call[:version].should be_nil
        call[:values].should be_empty

        # verify mock output matches what tests expect
        result.should contain("ARG: template")
        result.should contain("ARG: jetstack/cert-manager")
        result.should contain("ARG: --include-crds")
      end

      it "includes version when provided" do
        mock_helm = MockHelm.new
        subject = TestableHelmsplit.new(helm: mock_helm)

        result_version = subject.test_render_chart("jetstack/cert-manager", "1.20", [] of String)

        mock_helm.template_calls.first[:version].should eq("1.20")
        result_version.should contain("ARG: --version")
        result_version.should contain("ARG: 1.20")
      end

      it "passes values files correctly and retains ordering" do
        mock_helm = MockHelm.new
        subject = TestableHelmsplit.new(helm: mock_helm)

        result = subject.test_render_chart("jetstack/cert-manager", nil, ["base.yaml", "prod.yaml"])

        mock_helm.template_calls.first[:values].should eq(["base.yaml", "prod.yaml"])
        result.should contain("ARG: --values=base.yaml")
        result.should contain("ARG: --values=prod.yaml")
        result.index!("--values=base.yaml").should be < result.index!("--values=prod.yaml")
      end

      context "when helm exits non-zero" do
        it "raises HelmsplitError containing exit code and stderr" do
          mock_helm = MockHelm.new

          # assert the failure case
          mock_helm.should_fail = true
          subject = TestableHelmsplit.new(helm: mock_helm)

          expect_raises(Crux::Commands::Helmsplit::HelmsplitError, /helm template failed with exit code 1.*bogustown/m) do
            subject.test_render_chart("def-missing-chart-bro", nil, [] of String)
          end
        end
      end
    end
  end

  describe "#sanitize_rendered" do
    subject = TestableHelmsplit.new

    context "pass 1: substring pruning" do
      it "strips 'RELEASE-NAME-' without dropping the line" do
        subject.test_sanitize_rendered("  name: RELEASE-NAME-my-app\n").should eq("  name: my-app\n")
      end

      it "strips 'release-name-' without dropping the line" do
        subject.test_sanitize_rendered("  name: release-name-my-app\n").should eq("  name: my-app\n")
      end
    end

    context "pass 2: whole line drop" do
      it "drops lines containing 'helm'" do
        input = <<-EOF
          metadata:
            annotations:
              helm.sh/chart: cert-manager
              other: value
          EOF
        subject.test_sanitize_rendered(input)
          .should eq("metadata:\n  annotations:\n    other: value")
      end

      it "drops '# Source:' comments that helm emits between docs" do
        input = "# Source: cert-manager/whatever.yaml\napiVersion: v1"
        subject.test_sanitize_rendered(input)
          .should eq("apiVersion: v1")
      end
    end

    context "interaction between passes 1 and 2" do
      it "applies purne before drop so a pruned line survives" do
        subject.test_sanitize_rendered("  name: RELEASE-NAME-my-app\n")
          .should eq("  name: my-app\n")
      end

      it "still drops a line when pass 1 tokens survive pruning" do
        # pass 1 removes 'release-name-' leaving ' name: helm-app'
        # pass 2 removes 'helm' and drops the whole line
        subject.test_sanitize_rendered("  name: release-name-helm-app\nkeep: me\n")
          .should eq("keep: me\n")
      end
    end
  end

  describe "#write_provenance", tags: "io" do
    workdir = ""

    before_each do
      workdir = File.join(Dir.tempdir, "helmsplit_prov_#{Time.utc.to_unix_ms}")
      Dir.mkdir_p(workdir)
    end

    after_each do
      FileUtils.rm_rf(workdir) if Dir.exists?(workdir)
    end

    it "records the -o overrides flag when present" do
      TestableHelmsplit.new.test_write_provenance(workdir, "repo/chart", nil, [] of String, nil, "overrides.kyaml")
      File.read(File.join(workdir, "_PROVENANCE.md")).should contain("-o overrides.kyaml")
    end

    it "omits the -o flag when absent" do
      TestableHelmsplit.new.test_write_provenance(workdir, "repo/chart", nil, [] of String, nil, nil)
      File.read(File.join(workdir, "_PROVENANCE.md")).should_not contain("-o")
    end
  end

  describe "record emission verification", tags: "io" do
    workdir = ""
    outdir = ""
    before_each do
      workdir = File.join(Dir.tempdir, "helmsplit_record_spec_#{Time.utc.to_unix_ms}")
      outdir = File.join(workdir, "outdir")
      Dir.mkdir_p(outdir)
    end

    after_each do
      FileUtils.rm_rf(workdir) if Dir.exists?(workdir)
    end

    it "reports missing Helm executable" do
      helm = MockHelm.new
      helm.installed = false

      status, output, _errors = execute_helmsplit(
        [outdir, "repo/chart"],
        helm,
      )

      status.should eq(1)
      output.should contain("ERRO Executable not found")
      output.should contain("executable=helm")
    end

    it "reports Helm processing failures" do
      helm = MockHelm.new
      helm.should_fail = true

      status, output, _errors = execute_helmsplit(
        [outdir, "repo/chart"],
        helm,
      )

      status.should eq(1)
      output.should contain("err=")
      output.should contain("helm template failed with exit code 1")
      output.should contain("chart not found")
    end

    it "reports override failures" do
      helm = MockHelm.new
      helm.rendered_output = KubeManifestFixtures::VALID_SINGLE_DOC

      overrides = File.join(workdir, "overrides.kyaml")
      File.write(overrides, <<-KYAML)
        ---
        {
          clusters: ["c1"],
          output: "#{outdir}/overrides/${cluster}/override-${object}.yaml",
          overrides: [{
            configmap: "does-not-exist-will-error",
            patches: [{
              outerPath: "data[config.yaml]",
              innerPath: "name",
              value: "replacement",
            }],
          }],
        }
        KYAML

      status, output, _errors = execute_helmsplit(
        [outdir, "repo/chart", "--overrides", overrides],
        helm,
      )

      status.should eq(1)
      output.should contain("INFO Written")
      output.should contain("ERRO Overrides processing failed")
      output.should contain("ConfigMap source file not found")
      # This execution failed, it should never emit a success record.
      output.should_not contain("INFO Processing complete")

      # The mocked chart "exists" so rendering was successful, only the override sub-step failed.
      File.exists?(File.join(outdir, "my-app-deployment.yaml")).should be_true
      File.exists?(File.join(outdir, "_PROVENANCE.md")).should be_true
    end

    it "emits manifest, override, and completion records after execution" do
      helm = MockHelm.new
      # We're not gonna pass in a real helm chart to render, so let's just pretend it happened.
      helm.rendered_output = KubeManifestFixtures::CONFIGMAP_MULTILINE_DOC

      overrides = File.join(workdir, "overrides.kyaml")
      File.write(overrides, <<-KYAML)
        ---
        {
          clusters: ["c1"],
          output: "#{outdir}/overrides/${cluster}/override-${object}.yaml",
          overrides: [{
            configmap: "shield-cluster",
            patches: [{
              outerPath: "data[cluster-shield.yaml]",
              innerPath: "cluster_config.name",
              valueFrom: "cluster.name"
            }],
          }],
        }
        KYAML

      status, output, _errors = execute_helmsplit(
        [outdir, "repo/chart", "--overrides", overrides],
        helm,
      )

      status.should eq(0)
      lines = output.lines
      lines.size.should eq(3)
      lines[0].should contain("INFO Written")
      lines[1].should contain("INFO Written")
      lines[1].should contain("cluster=c1")
      lines[2].should contain("INFO Processing complete")
      lines[2].should contain("written=1")
      lines[2].should contain("skipped=0")

      File.exists?(File.join(outdir, "shield-cluster-configmap.yaml")).should be_true
      File.exists?(File.join(outdir, "overrides", "c1", "override-shield-cluster.yaml")).should be_true
      File.exists?(File.join(outdir, "_PROVENANCE.md")).should be_true
    end
  end
end
