require "yaml"

module Crux::Kube
  # Encapsulates the core YAML splitting logic, separated from the CLI command class so it can be tested independently.
  #
  # Given a multi-doc YAML string, splits each document into its own `<metadata.name>-<kind>.yaml` file into a destination *outdir* (with optional *prefix* applied to each file).
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

    # Splits multi-doc YAML *content* into distinct files in `@outdir` and emits operational records through *logger*.
    #
    # Docs that are null/empty or invalid K8s manifests are skipped with a warning. Raises when *content* is malformed.
    #
    # Returns a NamedTuple of `{written: count, skipped: count}`.
    def process(content : String, logger : Etch::Logger) : {written: Int32, skipped: Int32}
      Dir.mkdir_p(@outdir)

      docs = YAML.parse_all(content)
      written = 0
      skipped = 0

      docs.each_with_index do |doc, i|
        # Null docs occur from bare --- separators.
        # Silently skip them.
        next if doc.raw.nil?
        document = i + 1
        k8s_doc = Crux::Kube::K8sDoc.from_yaml(doc.to_yaml)

        unless k8s_doc.valid?
          logger.warn "Skipping invalid doc",
            document: document,
            required_fields: "apiVersion, kind, metadata.name"
          skipped += 1
          next
        end

        unless safe_resource_name?(k8s_doc.resource_name)
          logger.warn "Skipping doc with invalid resource name",
            document: document,
            name: k8s_doc.resource_name
          skipped += 1
          next
        end

        filename = build_filename(k8s_doc.resource_name, k8s_doc.resource_kind)

        unless write_path_inside_outdir?(filename)
          logger.warn "Skipping doc outside output dir",
            document: document,
            path: filename
          skipped += 1
          next
        end

        begin
          # ConfigMaps may carry embedded YAML blobs as double-quoted flow style scalars.
          # Normalize to literal block scalar style for readability.
          rendered = k8s_doc.resource_kind == "ConfigMap" ? Crux::Kube::YamlBlock.emit(doc) : doc.to_yaml
          File.write(filename, rendered)
          logger.info "Written", path: filename
          written += 1
        rescue ex : Exception
          logger.warn "Failed to write",
            path: filename,
            err: ex
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
