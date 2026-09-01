require "kyaml"
require "yaml"

module Crux::Kube::ConfigMapOverrides
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
      if value && value_from
        raise ProcessorError.new(
          "patch (outerPath=#{outer_path}, innerPath=#{inner_path}) has both 'value' and 'valueFrom' set. Exactly one is required."
        )
      end

      unless value || value_from
        raise ProcessorError.new(
          "patch (outerPath=#{outer_path}, innerPath=#{inner_path}) has neither 'value' nor 'valueFrom' set. Exactly one is required."
        )
      end

      if (vf = value_from) && vf != SUPPORTED_VALUE_FROM
        raise ProcessorError.new(
          "unsupported valueFrom ref '#{vf}'. Only #{SUPPORTED_VALUE_FROM} is supported."
        )
      end
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
      overrides.each do |entry|
        entry.patches.each do |patch|
          patch.validate!
        end
      end
    end

    # Reads and parses an overrides file, then validates it.
    #
    # Raises on missing file or KYAML parsing errors.
    def self.load(path : String) : OverridesConfig
      raise ProcessorError.new("overrides file not found: #{path}") unless File.exists?(path)

      config = from_kyaml(File.read(path))
      config.validate!
      config
    rescue ex : KYAML::ParseError | YAML::ParseException
      raise ProcessorError.new("invalid override config file '#{path}': #{ex.message}")
    end
  end

  # Orchestrates the per-cluster, per-override patch generation pipeline.
  class Processor
    # Matches outerPath on the form `data[<key>]` to capture the literal key being patched.

    OUTER_PATH_PATTERN = /\Adata\[([^\]]+)\]\z/

    def initialize(@outdir : String)
    end

    # Extracts the literal data key from outerPath on the form `data[<key>]`.
    #
    # Raises on any other form.
    def self.parse_outer_key(outer_path : String) : String
      match = OUTER_PATH_PATTERN.match(outer_path)
      unless match
        raise ProcessorError.new("expected form 'data[<key>]', invalid outerPath '#{outer_path}'")
      end
      match[1]
    end

    # Splits an innerPath into dot-delimited segments.
    #
    # Raises on empty path or empty segments.
    def self.parse_inner_path(inner_path : String) : Array(String)
      segments = inner_path.split('.')
      if inner_path.empty? || segments.any?(&.empty?)
        raise ProcessorError.new("expected dot-separated keys, invalid innerPath '#{inner_path}'")
      end
      segments
    end

    # Reads, validates, and applies an overrides config, writing one Configmap patch file per cluster+override-entry pair.
    #
    # Raises on any error, leaving prior writes in place.
    def process(overrides_path : String, out_io : IO = STDOUT, err_io : IO = STDERR) : Nil
      config = OverridesConfig.load(overrides_path)

      config.clusters.each do |cluster|
        config.overrides.each do |entry|
          write_entry(config, cluster, entry, out_io)
        end
      end
    end

    # Generates and writes one patch file for a single cluster+entry pair.
    private def write_entry(config : OverridesConfig, cluster : String, entry : OverrideEntry, out_io : IO) : Nil
      source = File.join(@outdir, "#{entry.configmap}-configmap.yaml")
      unless File.file?(source)
        raise ProcessorError.new("ConfigMap source file not found: #{source}")
      end

      configmap = YAML.parse(File.read(source))
      patched_data = {} of String => String

      # Group patches by their target data key so each inner blob is parsed once and accumulates all mutations before re-emission.
      grouped = entry.patches.group_by do |patch|
        self.class.parse_outer_key(patch.outer_path)
      end
      grouped.each do |data_key, patches|
        inner = read_inner(configmap, data_key, entry.configmap)
        patches.each do |patch|
          # Since `validate!` guarantees that only one of value/value_from is set, nil always means "use the cluster name"
          resolved = patch.value || cluster
          set_inner_value(inner, patch.inner_path, resolved)
        end
        patched_data[data_key] = Crux::Kube::YamlBlock.emit(inner).lchop("---\n")
      end

      # TODO: the naive way saves the day for now. At some point let's probably do something more elegant than matching a static list of strings defined here.
      output_path = config.output.gsub("${cluster}", cluster).gsub("${object}", entry.configmap)
      Dir.mkdir_p(File.dirname(output_path))
      File.write(output_path, build_patch(entry.configmap, patched_data))
      out_io.puts "Written: #{output_path}"
    end

    # Reads and parses the embedded YAML string at `data[<data_key>]` in the configmap.
    #
    # Raises ProcessorError if the data key is not found, value is not a string, or is invalid YAML.
    private def read_inner(configmap : YAML::Any, data_key : String, configmap_name : String) : YAML::Any
      data = configmap["data"]
      unless data && data.as_h?
        raise ProcessorError.new("ConfigMap '#{configmap_name}' has no 'data' mapping")
      end

      raw = data[data_key]?
      unless raw
        raise ProcessorError.new("ConfigMap '#{configmap_name}' has no data key '#{data_key}'")
      end

      str = raw.as_s?
      unless str
        raise ProcessorError.new("Configmap '#{configmap_name}' data key '#{data_key}' is not a string")
      end

      YAML.parse(str)
    rescue ex : YAML::ParseException
      raise ProcessorError.new("ConfigMap '#{configmap_name}' data key '#{data_key}' is not valid YAML: #{ex.message}")
    end

    # Sets a mutated-in-place `value` at `inner_path` within a parsed inner doc.
    # Ensures that each level of the dotted innerPath down to the leaf value is present, and that all levels above the leaf are a hash.
    #
    # Raises if any intermediate innerPath segment or leaf key is missing.
    private def set_inner_value(inner : YAML::Any, inner_path : String, value : String) : Nil
      segments = self.class.parse_inner_path(inner_path)

      cursor = inner
      segments[0...-1].each do |seg|
        nxt = cursor[seg]?
        unless nxt && nxt.as_h?
          raise ProcessorError.new("innerPath '#{inner_path}': segment '#{seg}' not found")
        end
        cursor = nxt
      end

      unless hash = cursor.as_h?
        raise ProcessorError.new("innerPath '#{inner_path}': parent is not a mapping")
      end

      leaf = segments.last
      unless hash.has_key?(YAML::Any.new(leaf))
        raise ProcessorError.new("innerPath '#{inner_path}': key '#{leaf}' not found")
      end

      hash[YAML::Any.new(leaf)] = YAML::Any.new(value)
    end

    # Emits a minimal ConfigMap strategic-merge patch containing only the given data keys. Each value is rendered as a literal block scalar.
    private def build_patch(name : String, data : Hash(String, String)) : String
      YAML.build do |builder|
        builder.mapping do
          builder.scalar "apiVersion"
          builder.scalar "v1"
          builder.scalar "kind"
          builder.scalar "ConfigMap"
          builder.scalar "metadata"
          builder.mapping do
            builder.scalar "name"
            builder.scalar name
          end
          builder.scalar "data"
          builder.mapping do
            data.each do |k, v|
              builder.scalar k
              builder.scalar v, style: YAML::ScalarStyle::LITERAL
            end
          end
        end
      end
    end
  end
end
