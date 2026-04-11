require "file_utils"
require "http/client"
require "uri"
require "yaml"

module Crux::Commands
  class Ysplit < Kube
    # Base domain exception
    class YsplitError < Exception
    end

    # Use standard YAML::ParseException when YAML parsing fails.

    # For catching failures when the YAML doc is valid but is not a semantically valid K8s object
    class K8sDocumentError < YsplitError
    end

    # Represents the minimum required Kubernetes document YAML manifest with kind and metadata.name.
    struct K8sDoc
      include YAML::Serializable

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
    end

    # Encapsulates the core YAML splitting logic, separated from the CLI command class so it can be tested independently.
    #
    # Given a multi-doc YAML string, splits each document into its own `<metadata.name>-<kind>.yaml` file (with optional prefix).
    struct YsplitProcessor
      getter prefix : String?
      getter outdir : String

      def initialize(@outdir : String, @prefix : String? = nil)
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

          api_version = doc["apiVersion"]?.try(&.as_s?)
          kind = doc["kind"]?.try(&.as_s?)
          name = doc["metadata"]?.try(&.["name"]?).try(&.as_s?)

          unless api_version && kind && name
            err_io.puts "Document #{i + 1} is invalid."
            err_io.puts "Missing 'apiVersion', 'kind' or 'metadata.name' fields, skipping.\n"
            skipped += 1
            next
          end

          filename = build_filename(name, kind)

          begin
            File.write(filename, doc.to_yaml)
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
        base = @prefix ? "#{@prefix}-#{resource_name}-#{kind}" : "#{resource_name}-#{kind}".downcase

        Path.new(@outdir, "#{base}.yaml")
      end
    end

    #
    def setup : Nil
      @name = "ysplit"
      @summary = "split multi-doc YAML manifests into one file per object"
      @description = <<-DESC
        Splits multi-document Kubernetes YAML manifests into multiple separate local files.
        Outputs one valid YAML manifest file per detected K8s object.
        DESC

      add_usage "crux kube ysplit <outdir> [options]"
      add_usage ""
      add_usage "EXAMPLES"
      add_usage "crux kube ysplit . -f megafile.yaml"
      add_usage "crux kube ysplit ~/Desktop -r https://example.com/somefiles.yaml"

      add_argument "outdir", description: "path to save generated output files", required: true

      add_option 'f', "file", description: "the local path to a source YAML mega-manifest file", type: :single
      add_option 'p', "prefix", description: "a custom prefix added to each output filename", type: :single
      add_option 'r', "remote", description: "the HTTP/S URL to fetch a remote YAML manifest from", type: :single
    end

    def pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      if options.has? "help"
        stdout.puts help_template
        exit_program 0
      end
      @debug = true if options.has? "debug"
      Colorize.enabled = false if options.has? "no-color"

      # Handle the required but mutual-exclusivity of file and remote options early
      has_file = options.has?("file")
      has_remote = options.has?("remote")

      if has_file && has_remote
        error "Options are mutually exclusive:"
        error "\t#{"-f|--file".colorize.red} and #{"-r|--remote".colorize.red}"
        error "See #{"'crux kube ysplit --help'".colorize.blue.bold} for more help \n"
      end

      unless has_file || has_remote
        error "Missing required option:"
        error "\t#{"-f|--file".colorize.red} or #{"-r|--remote".colorize.red}"
        error "See #{"'crux kube ysplit --help'".colorize.blue.bold} for more help \n"
      end
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      prefix = options.get?("prefix").try(&.as_s?)
      outdir = arguments.get("outdir").as_s

      content = if options.has?("file")
                  path = options.get("file").as_s
                  read_local_file(path)
                elsif options.has?("remote")
                  url = URI.parse options.get("remote").as_s
                  validate_yaml_url(url)

                  fetch_remote(url)
                else
                  exit_program
                end
      processor = YsplitProcessor.new(outdir, prefix)
      result = processor.process(content, stdout, stderr)
      result[:written]
      result[:skipped]

      count_label = result[:written] == 1 ? "1 file" : "#{result[:written]} files"
      info "Complete: #{count_label} written, #{result[:skipped]} skipped."
    rescue ex : YsplitError
      error "#{"Processing Error:".colorize.bold}"
      error "\t#{ex.message}"
      exit_program
    rescue ex : K8sDocumentError
      error "#{"Kube Manifest Error:".colorize.bold}"
      error "\t#{ex.message}"
      exit_program
    end

    def post_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    # Validate that the user-provided URL is an HTTP endpoint and likely contains YAML
    def validate_yaml_url(url : URI) : String
      valid_scheme : Regex = /^https?$/
      if url.scheme.try { |scheme| valid_scheme.matches?(scheme) } &&
         url.host &&
         url.path.split(".").last.downcase == "yaml"
        url.to_s
      else
        raise YsplitError.new("'#{url.to_s.colorize.red}' is not a valid url containing YAML")
      end
    end

    # Reads YAML content from a local file path (supports ~/ homedir expansion)
    # Returns the file contents.
    private def read_local_file(path : String) : String
      expanded = File.expand_path(path)
      begin
        File.read(expanded)
      rescue File::NotFoundError
        error "File not found: #{path}"
        exit_program 1
      rescue ex : Exception
        error "Could not read file: '#{path}': #{ex.message}"
        exit_program 1
      end
    end

    # Fetches YAML content from a remote HTTP or HTTPS URL.
    # Returns the HTTP response body.
    # Exits with an error on network failure or non-2XX status code
    private def fetch_remote(url : URI) : String
      # TODO: Build redirect-following logic, checking `Location` header for redirects on each 3xx response. Github releases redirec fails

      response = HTTP::Client.get(url)
      unless response.success?
        error "HTTP #{response.status_code}: #{response.body}"
        exit_program 1
      end
      response.body
    rescue ex : Exception
      error "Network error fetching '#{url}': #{ex.message}"
      exit_program 1
    end
  end
end
