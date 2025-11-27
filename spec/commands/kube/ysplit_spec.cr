require "../../spec_helper"

describe Crux::Commands::Ysplit do
  subject = Crux::Commands::Ysplit.new

  describe "#validate_yaml_url" do
    context "with valid URLS" do
      it "accepts http:// URL with .yaml extension" do
        url = URI.parse("http://example.com/manifests.yaml")
        result = subject.validate_yaml_url(url)
        result.should be_truthy
      end

      it "accepts https:// URL with .yaml extension" do
        url = URI.parse("https://raw.githubusercontent.com/org/repo/branch/deploy.yaml")
        result = subject.validate_yaml_url(url)
        result.should be_truthy
      end

      it "accepts .YAML extension (case-insensitive)" do
        url = URI.parse("http://example.com/manifests.YAML")
        result = subject.validate_yaml_url(url)
        result.should be_truthy
      end
    end

    context "with invalid URLS" do
      it "rejects non http(s):// scheme" do
        url = URI.parse("ftp://example.com/file.yaml")
        expect_raises(Crux::Commands::Ysplit::YSplitError) do
          result = subject.validate_yaml_url(url)
        end
      end

      it "rejects URL without .yaml extension" do
        url = URI.parse("https://example.com/file.json")
        expect_raises(Crux::Commands::Ysplit::YSplitError) do
          result = subject.validate_yaml_url(url)
        end
      end

      it "rejects URL without valid host" do
        url = URI.parse("/just/a/path.yaml")
        expect_raises(Crux::Commands::Ysplit::YSplitError) do
          subject.validate_yaml_url(url)
        end
      end
    end
  end

  describe "read_remote_yaml" do
  end

  describe "read_local_yaml" do
  end

  describe "process_yaml" do
  end

  describe "write_yaml" do
  end
end
