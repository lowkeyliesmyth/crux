require "kyaml"

module Crux::Commands::ConfigMapOverrides
  class ProcessorError < Exception
  end

  # Single patch operation: set the value at `inner_path` within the blob found at `outer_path`.
  #
  # `value` and `value_from` are mutually exclusive.
  struct Patch
    include KYAML::Serializable

    @[KYAML::Field(key: "outerPath")]
    getter outer_path : String

    @[KYAML::Field(key: "innerPath")]
    getter inner_path : String

    getter value : String?

    @[KYAML::Field(key: "valueFrom")]
    getter value_from : String?

    # The ONLY supported `valueFrom` ref
    SUPPORTED_VALUE_FROM = "cluster.name"

    # Validates mutual exclusivity of `value` and `value_from`
    #
    # Raises on violations.
    def validate! : Nil
      raise NotImplementedError.new("Patch#validate!")
    end
  end

  # ConfigMap target and the patches to apply to it.
  struct OverrideEntry
    include KYAML::Serializable

    getter configmap : String
    getter patches : Array(Patch)
  end

  # Parsed representation of the user's overrides.kyaml config doc.
  struct OverridesConfig
    include KYAML::Serializable

    getter clusters : Array(String)
    getter output : String
    getter overrides : Array(OverrideEntry)

    # Validates every patch across every oerride entry
    #
    # Raises on the first violation found.
    def validate! : Nil
      raise NotImplementedError.new("OverrideConfig#validate!")
    end

    # Reads and parses an overrides file, then validates it.
    #
    # Raises on missing file or KYAML parsing errors.
    def self.load(path : String) : OverridesConfig
      raise NotImplementedError.new("OverridesConfig.load")
    end
  end
end
