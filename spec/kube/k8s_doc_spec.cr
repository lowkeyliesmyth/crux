require "../spec_helper"
require "../support/kube_manifest_fixtures"

describe Crux::Kube::K8sDoc do
  describe "#valid?" do
    it "returns true when all required fields are present" do
      doc = Crux::Kube::K8sDoc.from_yaml(KubeManifestFixtures::VALID_SINGLE_DOC)
      doc.valid?.should be_true
    end

    it "returns false when required apiVersion is missing" do
      doc = Crux::Kube::K8sDoc.from_yaml(KubeManifestFixtures::MISSING_API_VERSION_DOC)
      doc.valid?.should be_false
    end

    it "returns false when required kind is missing" do
      doc = Crux::Kube::K8sDoc.from_yaml(KubeManifestFixtures::MISSING_KIND_DOC)

      doc.valid?.should be_false
    end

    it "returns false when required metadata is missing" do
      doc = Crux::Kube::K8sDoc.from_yaml(KubeManifestFixtures::MISSING_METADATA_DOC)

      doc.valid?.should be_false
    end

    it "returns false when required metadata.name is missing or null" do
      doc1 = Crux::Kube::K8sDoc.from_yaml(KubeManifestFixtures::MISSING_NAME_DOC)
      doc2 = Crux::Kube::K8sDoc.from_yaml(KubeManifestFixtures::NULL_NAME_DOC)

      doc1.valid?.should be_false
      doc2.valid?.should be_false
    end
  end

  describe ".from_yaml" do
    it "raises when YAML is malformed" do
      expect_raises(YAML::ParseException) do
        Crux::Kube::K8sDoc.from_yaml(KubeManifestFixtures::MALFORMED_YAML)
      end
    end
  end
end
