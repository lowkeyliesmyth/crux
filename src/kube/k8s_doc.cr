require "yaml"

module Crux::Kube
  # Represents the minimum required Kubernetes document YAML manifest with apiVersion, kind, and metadata.name.
  struct K8sDoc
    include YAML::Serializable

    # ameba:disable Naming/VariableNames
    getter apiVersion : String?
    getter kind : String?
    getter metadata : Metadata?

    struct Metadata
      include YAML::Serializable
      getter name : String?
    end

    # Returns `true` if the doc meets the minimum required fields for a valid K8s object
    def valid? : Bool
      !apiVersion.nil? && !kind.nil? && !metadata.try(&.name).nil?
    end

    # Returns `metadata.name`. Only safe to call after `valid?` returns true.
    def resource_name : String
      # ameba:disable Lint/NotNil
      metadata.not_nil!.name.not_nil!
    end

    # Returns `kind`. Only safe to call after `valid?` returns true.
    def resource_kind : String
      # ameba:disable Lint/NotNil
      kind.not_nil!
    end
  end
end
