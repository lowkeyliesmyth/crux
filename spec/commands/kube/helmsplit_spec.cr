require "../../spec_helper"
require "file_utils"

# Test subclass wrapping and exposing private methods in Helmsplit

class TestableHelmsplit < Crux::Commands::Helmsplit
  def test_resolve_chart(chart : String) : String
    String
    resolve_chart(chart)
  end

  def test_render_chart(chart : String, version : String?, values : Array(String)) : String
    render_chart(chart, version, values)
  end

  def test_sanitize_rendered(rendered : String) : String
    sanitize_rendered(rendered)
  end
end

# TODO: Refactor this test and the source helmsplit to use an abstract collaborator pattern
# Crappy temporary shell-based fake for the external `helm` command
# Writes a shellscript to <tmpdir>/helm, prepends <tmpdir> to PATH. Restores PATH afterwards
private def with_fake_helm(body : String, &)
  tmpdir = File.join(Dir.tempdir, "helmsplit_fake_helm_#{Time.utc.to_unix_ms}_#{rand(10_000)}")
  Dir.mkdir_p(tmpdir)
  path = File.join(tmpdir, "helm")
  File.write(path, body)
  File.chmod(path, 0o755)

  original = ENV["PATH"] || ""
  ENV["PATH"] = "#{tmpdir}:#{original}"
  begin
    yield
  ensure
    ENV["PATH"] = original
    FileUtils.rm_rf(tmpdir)
  end
end

# Echoes each argv entry on its own line so tests can assert flag render_chart contract constructs.
FAKE_HELM_ECHO_ARGS = <<-'EOF'
  #!/bin/sh
  for arg in "$@"; do
    printf 'ARG:%s\\n' "$arg"
  done
  EOF

# Intentionally fails with a non-zero and a defined stderr payload.
FAKE_HELM_FAIL = <<-EOF
  #!/bin/sh
  echo 'Error: chart not found: bogustown' >&2
  exit 1
  EOF

describe Crux::Commands::Helmsplit do
  describe "#resolve_chart" do
    subject = TestableHelmsplit.new
    tmpdir = ""

    before_each do
      tmpdir = File.join(Dir.tempdir, "helmsplit_resolve_spec_#{Time.utc.to_unix_ms}")
      Dir.mkdir_p(tmpdir)
    end

    after_each do
      FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
    end

    context "with a valid local chart directory" do
      it "returns the expanded absolute path" do
        File.write(File.join(tmpdir, "Chart.yaml"), "name: fake\nversion:  0.0.1\n")
        subject.test_resolve_chart(tmpdir).should eq(File.expand_path(tmpdir))
      end
    end

    context "with a local dir missing a Chart.yaml" do
      it "raises HelmsplitError calling out Chart.yaml requirement" do
        expect_raises(Crux::Commands::Helmsplit::HelmsplitError, /Missing Chart.yaml/) do
          subject.test_resolve_chart(tmpdir)
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
      it "returns helm's stdout" do
        with_fake_helm(FAKE_HELM_ECHO_ARGS) do
          result = subject.test_render_chart("jetstack/cert-manager", nil, [] of String)
          result.should contain("ARG:template")
          result.should contain("ARG:jetstack/cert-manager")
        end
      end

      it "always passes --include-crds flag to helm" do
        with_fake_helm(FAKE_HELM_ECHO_ARGS) do
          result = subject.test_render_chart("jetstack/cert-manager", nil, [] of String)
          result.should contain("ARG:--include-crds")
        end
      end

      it "includes --version <v> only when a version is provided" do
        with_fake_helm(FAKE_HELM_ECHO_ARGS) do
          result_version = subject.test_render_chart("jetstack/cert-manager", "1.20", [] of String)
          result_version.should contain("ARG:--version")
          result_version.should contain("ARG:1.20")

          no_version = subject.test_render_chart("jetstack/cert-manager", nil, [] of String)
          no_version.should_not contain("ARG:--version")
        end
      end

      it "emits single ordered --values=<path> per entry" do
        with_fake_helm(FAKE_HELM_ECHO_ARGS) do
          result = subject.test_render_chart("jetstack/cert-manager", nil, ["base.yaml", "prod.yaml"])
          result.should contain("ARG:--values=base.yaml")
          result.should contain("ARG:--values=prod.yaml")
          # confirm ordering, not just content
          result.index!("--values=base.yaml").should be < result.index!("--values=prod.yaml")
        end
      end
    end

    context "when helm exits non-zero" do
      it "raises HelmsplitError containing exit code" do
        with_fake_helm(FAKE_HELM_FAIL) do
          expect_raises(Crux::Commands::Helmsplit::HelmsplitError, /exit code 1/) do
            subject.test_render_chart("definitely-missing-chart", nil, [] of String)
          end
        end
      end

      it "surfaces helm's stderr text in the raised message" do
        with_fake_helm(FAKE_HELM_FAIL) do
          expect_raises(Crux::Commands::Helmsplit::HelmsplitError, /bogustown/) do
            subject.test_render_chart("definitely-missing-chart", nil, [] of String)
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

      it "still drops a line when pass 2 tokens survive pruning" do
        # pass 1 removes 'release-name-' leaving ' name: helm-app'
        # pass 2 removes 'helm' and drops the whole line
        subject.test_sanitize_rendered("  name: release-name-helm-app\nkeep: me\n")
          .should eq("keep: me\n")
      end
    end
  end
end
