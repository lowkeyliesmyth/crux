require "../../spec_helper"

# Concrete overrides config example, targeting configmaps rendered out from the sysdig shield chart (https://charts.sysdig.com/charts/shield/) as the source.
# ---
# {
#  clusters: [
#    "cluster1",
#    "cluster2",
#  ],
#  output: "subsystems/sysdig/clusters/${cluster}/patches/override-${object}.yaml",
#  overrides: [{
#    configmap: "shield-cluster",
#    patches: [{
#      outerPath: "data[cluster-shield.yaml]",
#      innerPath: "cluster_config.name",
#      valueFrom: "cluster.name",
#    }, {
#      outerPath: "data[cluster-shield.yaml]",
#      innerPath: "kubernetes.running_namespace",
#      value: "sysdig",
#    }],
#  }, {
#    configmap: "shield-host",
#    patches: [{
#      outerPath: "data[dragent.yaml]",
#      innerPath: "k8s_cluster_name",
#      valueFrom: "cluster.name",
#    }],
#  }],
# }

# Builds a one-patch overrides doc template wrapper around a provided patch body
private def overrides_doc(patch : String) : String
  <<-KYAML
  ---
  {
    clusters: ["c1"],
    output: "out/${cluster}/${object}.yaml",
    overrides: [{
      configmap: "shield",
      patches: [#{patch}],
    }],
  }
  KYAML
end

describe Crux::Commands::ConfigMapOverrides::OverridesConfig do
  describe "#from_kyaml" do
    it "parses the user provided overrides config doc" do
      config = Crux::Commands::ConfigMapOverrides::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster.namespace", value: "foo"}))
      )

      config.clusters.should eq(["c1"])
      config.output.should eq("out/${cluster}/${object}.yaml")
      config.overrides.size.should eq(1)

      entry = config.overrides.first
      entry.configmap.should eq("shield")

      patch = entry.patches.first
      patch.outer_path.should eq("data[dragent.yaml]")
      patch.inner_path.should eq("cluster.namespace")
      patch.value.should eq("foo")
      patch.value_from.should be_nil
    end
  end
  describe "#validate!" do
    it "accepts a patch with only `value`" do
      config = Crux::Commands::ConfigMapOverrides::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster.namespace", value: "foo"}))
      )
      config.validate!
    end

    it "accepts a patch with only `valueFrom: cluster.name`" do
      config = Crux::Commands::ConfigMapOverrides::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster_config.name", valueFrom: "cluster.name"}))
      )
      config.validate!
    end

    it "raises when mutually-exclusive `value` and `valueFrom` are provided" do
      config = Crux::Commands::ConfigMapOverrides::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster.namespace", value: "foo", valueFrom: "cluster.name"}))
      )
      expect_raises(Crux::Commands::ConfigMapOverrides::ProcessorError, /both 'value' and 'valueFrom'/) do
        config.validate!
      end
    end

    it "raises when neither `value` nor `valueFrom` are provided" do
      config = Crux::Commands::ConfigMapOverrides::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster.namespace"}))
      )
      expect_raises(Crux::Commands::ConfigMapOverrides::ProcessorError, /neither 'value' nor 'valueFrom'/) do
        config.validate!
      end
    end

    it "raises on an unsupported valueFrom reference" do
      config = Crux::Commands::ConfigMapOverrides::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster_config.name", valueFrom: "cluster.region" }))
      )
      expect_raises(Crux::Commands::ConfigMapOverrides::ProcessorError, /unsupported valueFrom/) do
        config.validate!
      end
    end
  end

  describe "#load" do
    it "raises ProcessorError when the file is missing" do
      expect_raises(Crux::Commands::ConfigMapOverrides::ProcessorError, /not found/) do
        Crux::Commands::ConfigMapOverrides::OverridesConfig.load(
          "/path/to/missing/file-#{Time.utc.to_unix_ms}.yaml"
        )
      end
    end

    it "raises ProcessorError on invalid KYAML in override doc" do
      path = File.join(Dir.tempdir, "bad_overrides_#{Time.utc.to_unix_ms}.kyaml")
      File.write(path, "---\n{ output: \"x\", overrides: [] }")
      begin
        expect_raises(Crux::Commands::ConfigMapOverrides::ProcessorError, /invalid override config/) do
          Crux::Commands::ConfigMapOverrides::OverridesConfig.load(path)
        end
      ensure
        File.delete(path) if File.exists?(path)
      end
    end
  end
end
