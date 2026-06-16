require "../spec_helper"

describe Crux::Kube::YamlBlock do
  describe "#emit" do
    context "with a ConfigMap containing a multi-line data value" do
      it "emits the value as a literal block scalar" do
        src = <<-YAML
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: shield-cluster
          data:
            cluster-shield.yaml: "cluster_config:\\n name: foo\\n"
          YAML

        result = Crux::Kube::YamlBlock.emit(YAML.parse(src))

        result.should contain("cluster-shield.yaml: |")
        result.should contain("cluster_config:")
        result.should contain("name: foo")
      end
    end

    context "with a single-line string value" do
      it "keeps them inline" do
        result = Crux::Kube::YamlBlock.emit(YAML.parse("data:\n flat: just-a-value\n"))

        result.should contain("flat: just-a-value")
        result.should_not contain("|")
      end
    end

    context "idempotency" do
      it "round-tripping literal output yields the original value" do
        src = <<-YAML
          data:
            blob: |
              a: 1
              b: 2
          YAML

        once = Crux::Kube::YamlBlock.emit(YAML.parse(src))
        twice = Crux::Kube::YamlBlock.emit(YAML.parse(once))

        twice.should eq(once)
      end
    end

    context "with non-string scalars" do
      it "round-trips ints, bools, nested maps and sequences" do
        src = <<-YAML
          count: 3
          enabled: true
          nested:
            items:
              - a
              - b
          YAML

        round = YAML.parse(Crux::Kube::YamlBlock.emit(YAML.parse(src)))

        round["count"].as_i.should eq(3)
        round["enabled"].as_bool.should eq(true)
        round["nested"]["items"].as_a.map(&.as_s).should eq(["a", "b"])
      end
    end
  end
end
