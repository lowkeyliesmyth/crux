require "yaml"

module Crux::Kube
  # Encapsulates the core YAML splitting logic, separated from the CLI command class so it can be tested independently.
  #
  # Given a multi-doc YAML string, splits each document into its own `<metadata.name>-<kind>.yaml` file (with optional prefix).
  struct ManifestSplitter
    getter prefix : String?
    getter outdir : String

    def initialize(@outdir : String, @prefix : String? = nil)
    end

    # Regex for valid RFC 1123 subdomain names, which is used for the K8s metadata.name field
    # Used here to gate path construction and prevent a hostile manifest from writing outside of @outdir.
    # Notable exception: `:` is allowed because of names like `cert-manager:leaderelection`
    RFC_1123_SUBDOMAIN  = /\A[a-z0-9]([-a-z0-9:]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9:]*[a-z0-9])?)*\z/
    RFC_1123_MAX_LENGTH = 253

    # Returns true if `name` is a valid RFC-1123 DNS domain name
    private def safe_resource_name?(name : String) : Bool
      return false if name.empty? || name.bytesize > RFC_1123_MAX_LENGTH
      RFC_1123_SUBDOMAIN.matches?(name)
    end

    # Ensure `filename` is inside @outdir to prevent a hostile manifest from writing outside of it.
    # This should never happen, but defense in depth and whatnot.
    #
    # Returns true if `filename` is in @outdir as it should be, false otherwise.
    private def write_path_inside_outdir?(filename : Path) : Bool
      expanded_outdir = File.expand_path(@outdir)
      expanded_path = File.expand_path(filename.to_s)
      expanded_path.starts_with?(expanded_outdir)
    end

    # Processes a multi-doc YAML string and writes each doc to a separate file in outdir.
    # Docs that are null/empty or invalid K8s manifests are skipped with a warning.
    #
    # Returns a NamedTuple with the number of `written` and `skipped` docs.
    def process(content : String, out_io : IO = STDOUT, err_io : IO = STDERR) : {written: Int32, skipped: Int32}
      Dir.mkdir_p(@outdir)

      docs = YAML.parse_all(content)
      written = 0
      skipped = 0

      docs.each_with_index do |doc, i|
        # Null docs occur from bare --- separators
        # Silently skip them.
        next if doc.raw.nil?
        k8s_doc = Crux::Kube::K8sDoc.from_yaml(doc.to_yaml)

        unless k8s_doc.valid?
          err_io.puts "Document #{i + 1} is invalid."
          err_io.puts "Missing required 'apiVersion', 'kind' or 'metadata.name' fields, skipping.\n"
          skipped += 1
          next
        end

        unless safe_resource_name?(k8s_doc.resource_name)
          err_io.puts "Skipping: Doc #{i + 1} has an invalid 'metadata.name' (#{k8s_doc.resource_name}).\n"
          skipped += 1
          next
        end

        filename = build_filename(k8s_doc.resource_name, k8s_doc.resource_kind)

        unless write_path_inside_outdir?(filename)
          err_io.puts "Skipping: Doc #{i + 1} resolved to a path outside outdir (#{filename}).\n"
          skipped += 1
          next
        end

        # TODO: Update out_io formatting to match Crux::Commands::Base#info, and Crux::Commands::Base#error
        begin
          # ConfigMaps may carry embedded YAML blobs as double-quoted flow style scalars.
          # Normalize to literal block scalar style for readability.
          rendered = k8s_doc.resource_kind == "ConfigMap" ? Crux::Kube::YamlBlock.emit(doc) : doc.to_yaml
          File.write(filename, rendered)
          out_io.puts "Written: #{filename}\n"
          written += 1
        rescue ex : Exception
          err_io.puts "Failed to write #{filename}: #{ex.message}\n"
          skipped += 1
        end
      end
      {written: written, skipped: skipped}
    end

    # Generates a unique output file path for a K8s resource doc.
    #
    # Base pattern is: `<outdir>/<metadata.name>-<kind>.yaml`
    #
    # Pattern with optional prefix: `<outdir>/<prefix>-<metadata.name>-<kind>.yaml`
    def build_filename(resource_name : String, kind : String) : Path
      base = @prefix ? "#{@prefix}-#{resource_name.downcase}-#{kind.downcase}" : "#{resource_name}-#{kind}".downcase

      Path.new(@outdir, "#{base}.yaml")
    end
  end
end
