require "../spec_helper"
require "file_utils"
# Concrete reference source ConfigMap with nested yaml that needs to be overridden, based off of the sysdig shield chart (https://charts.sysdig.com/charts/shield/) as the source.
# apiVersion: v1
# kind: ConfigMap
# metadata:
#   name: shield-cluster
# data:
#   cluster-shield.yaml: |
#     cluster_config:
#       name: placeholder
#     kubernetes:
#       running_namespace: default

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

# This fully qualified class name is brutal. Make it suck less.
alias CMO = Crux::Kube::ConfigMapOverrides

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

describe CMO::OverridesConfig do
  describe "#from_kyaml" do
    it "parses the user provided overrides config doc" do
      config = CMO::OverridesConfig.from_kyaml(
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
      config = CMO::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster.namespace", value: "foo"}))
      )
      config.validate!
    end

    it "accepts a patch with only `valueFrom: cluster.name`" do
      config = CMO::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster_config.name", valueFrom: "cluster.name"}))
      )
      config.validate!
    end

    it "raises when mutually-exclusive `value` and `valueFrom` are provided" do
      config = CMO::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster.namespace", value: "foo", valueFrom: "cluster.name"}))
      )
      expect_raises(CMO::ProcessorError, /both 'value' and 'valueFrom'/) do
        config.validate!
      end
    end

    it "raises when neither `value` nor `valueFrom` are provided" do
      config = CMO::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster.namespace"}))
      )
      expect_raises(CMO::ProcessorError, /neither 'value' nor 'valueFrom'/) do
        config.validate!
      end
    end

    it "raises on an unsupported valueFrom reference" do
      config = CMO::OverridesConfig.from_kyaml(
        overrides_doc(%({ outerPath: "data[dragent.yaml]", innerPath: "cluster_config.name", valueFrom: "cluster.region" }))
      )
      expect_raises(CMO::ProcessorError, /unsupported valueFrom/) do
        config.validate!
      end
    end
  end

  describe "#load" do
    it "raises ProcessorError when the file is missing" do
      expect_raises(CMO::ProcessorError, /not found/) do
        CMO::OverridesConfig.load(
          "/path/to/missing/file-#{Time.utc.to_unix_ms}.yaml"
        )
      end
    end

    it "raises ProcessorError on invalid KYAML in override doc" do
      path = File.join(Dir.tempdir, "bad_overrides_#{Time.utc.to_unix_ms}.kyaml")
      File.write(path, "---\n{ output: \"x\", overrides: [] }")
      begin
        expect_raises(CMO::ProcessorError, /invalid override config/) do
          CMO::OverridesConfig.load(path)
        end
      ensure
        File.delete(path) if File.exists?(path)
      end
    end
  end
end

describe Crux::Kube::ConfigMapOverrides::Processor do
  describe "#parse_outer_key" do
    it "extracts the literal data key from data[<key>]" do
      CMO::Processor.parse_outer_key("data[cluster-shield.yaml]").should eq("cluster-shield.yaml")
    end

    it "treats dots inside brackets as literal chars, not delimiters" do
      CMO::Processor.parse_outer_key("data[a.b.yaml]").should eq("a.b.yaml")
    end

    it "raises on trailing traversal after the bracket" do
      expect_raises(CMO::ProcessorError, /expected form 'data\[<key>\]'/) do
        CMO::Processor.parse_outer_key("data[x].y")
      end
    end

    it "raises on an empty key" do
      expect_raises(CMO::ProcessorError, /expected form/) do
        CMO::Processor.parse_outer_key("data[]")
      end
    end

    it "raises when the root is not 'data'" do
      expect_raises(CMO::ProcessorError, /expected form/) do
        CMO::Processor.parse_outer_key("metadata[name]")
      end
    end
  end

  describe "#parse_inner_path" do
    it "splits a dotted path into segments" do
      CMO::Processor.parse_inner_path("cluster_config.name").should eq(["cluster_config", "name"])
    end

    it "returns a single segment for a flat key" do
      CMO::Processor.parse_inner_path("cluster_name").should eq(["cluster_name"])
    end

    it "raises on empty segments" do
      expect_raises(CMO::ProcessorError, /dot-separated keys/) do
        CMO::Processor.parse_inner_path("a..b")
      end
    end

    it "raises on an empty path" do
      expect_raises(CMO::ProcessorError, /dot-separated keys/) do
        CMO::Processor.parse_inner_path("")
      end
    end
  end

  describe "#process" do
    src_dir = ""
    out_dir = ""
    work = ""
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    # Writes a CM source file into src_dir. Data values are emitted as doublequoted flow-scalars so we can validate block-scalar normalization functionality.
    write_configmap = ->(name : String, data : Hash(String, String)) do
      body = String.build do |io|
        io << "apiVersion: v1\nkind: ConfigMap\nmetadata:\n name: #{name}\ndata:\n"
        data.each { |k, v| io << "  #{k}: #{v.inspect}\n" }
      end
      File.write(File.join(src_dir, "#{name}-configmap.yaml"), body)
    end

    write_overrides = ->(content : String) do
      path = File.join(work, "overrides.yaml")
      File.write(path, content)
      path
    end

    before_each do
      stamp = Time.utc.to_unix_ms
      src_dir = File.join(Dir.tempdir, "cmo_src_#{stamp}")
      out_dir = File.join(Dir.tempdir, "cmo_out_#{stamp}")
      work = File.join(Dir.tempdir, "cmo_work_#{stamp}")
      Dir.mkdir_p(src_dir)
      Dir.mkdir_p(out_dir)
      Dir.mkdir_p(work)
      out_io = IO::Memory.new
      err_io = IO::Memory.new
    end

    after_each do
      [src_dir, out_dir, work].each { |dir| FileUtils.rm_rf(dir) if Dir.exists?(dir) }
    end

    it "writes a patch for a single cluster + single literal-value patch" do
      write_configmap.call("shield-cluster", {"cluster-shield.yaml" => "cluster_config:\n  namespace: PLACEHOLDER\n"})
      path = write_overrides.call(<<-KYAML)
        ---
        {
          clusters: ["c1"],
          output: "#{out_dir}/${cluster}/override-${object}.yaml",
          overrides: [{
            configmap: "shield-cluster",
            patches: [{
              outerPath: "data[cluster-shield.yaml]",
              innerPath: "cluster_config.namespace",
              value: "foobar",
            }],
          }],
        }
        KYAML

      CMO::Processor.new(src_dir).process(path, out_io, err_io)
      generated = File.join(out_dir, "c1", "override-shield-cluster.yaml")
      File.exists?(generated).should be_true
      content = File.read(generated)
      content.should contain("cluster-shield.yaml: |")
      content.should contain("namespace: foobar")
    end

    it "resolves valueFrom: cluster.name across multiple clusters" do
      write_configmap.call("shield-host", {"dragent.yaml" => "k8s_cluster_name: PLACEHOLDER\n"})
      path = write_overrides.call(<<-KYAML)
        ---
        {
          clusters: [
            "c1",
            "c2",
          ],
          output: "#{out_dir}/${cluster}/override-${object}.yaml",
          overrides: [{
            configmap: "shield-host",
            patches: [{
              outerPath: "data[dragent.yaml]",
              innerPath: "k8s_cluster_name",
              valueFrom: "cluster.name",
            }],
          }],
        }
        KYAML

      CMO::Processor.new(src_dir).process(path, out_io, err_io)

      File.read(File.join(out_dir, "c1", "override-shield-host.yaml")).should contain("k8s_cluster_name: c1")
      File.read(File.join(out_dir, "c2", "override-shield-host.yaml")).should contain("k8s_cluster_name: c2")
    end

    it "includes only patched data keys in the output" do
      write_configmap.call("shield-cluster", {
        "cluster-shield.yaml" => "cluster_config:\n namespace: PLACEHOLDER\n",
        "other.yaml"          => "unrelated: true\n",
      })
      path = write_overrides.call(<<-KYAML)
        ---
        {
          clusters: ["c1"],
          output: "#{out_dir}/${cluster}/override-${object}.yaml",
          overrides: [{
            configmap: "shield-cluster",
            patches: [{
              outerPath: "data[cluster-shield.yaml]",
              innerPath: "cluster_config.namespace",
              value: "foobar",
            }],
          }],
        }
        KYAML

      CMO::Processor.new(src_dir).process(path, out_io, err_io)

      content = File.read(File.join(out_dir, "c1", "override-shield-cluster.yaml"))
      content.should contain("cluster-shield.yaml")
      content.should_not contain("other.yaml")
    end

    it "raises when the configmap source file is missing" do
      path = write_overrides.call(<<-KYAML)
        ---
        {
          clusters: ["c1"],
          output: "#{out_dir}/${cluster}/override-${object}.yaml",
          overrides: [{
            configmap: "does-not-exist",
            patches: [{
              outerPath: "data[a.yaml]",
              innerPath: "x",
              value: "v",
            }],
          }],
        }
        KYAML

      expect_raises(CMO::ProcessorError, /not found/) do
        CMO::Processor.new(src_dir).process(path, out_io, err_io)
      end
    end

    it "raises when the innerPath key does not exist" do
      write_configmap.call("shield-cluster", {"cluster-shield.yaml" => "cluster_config:\n  namespace: PLACEHOLDER\n"})
      path = write_overrides.call(<<-KYAML)
        ---
        {
          clusters: ["c1"],
          output: "#{out_dir}/${cluster}/override-${object}.yaml",
          overrides: [{
            configmap: "shield-cluster",
            patches: [{
              outerPath: "data[cluster-shield.yaml]",
              innerPath: "cluster_config.nope",
              value: "foobar",
            }],
          }],
        }
        KYAML

      expect_raises(CMO::ProcessorError, /not found/) do
        CMO::Processor.new(src_dir).process(path, out_io, err_io)
      end
    end
  end
end
