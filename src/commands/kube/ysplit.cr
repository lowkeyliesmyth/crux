require "file_utils"
require "http"
require "uri"
require "yaml"

module Crux::Commands
  # class Ysplit < Base
  class Ysplit < Kube
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
      if options.has?("file") && options.has?("remote")
        error "Options are mutually exclusive:"
        error "\t#{"-f|--file".colorize.red} and #{"-r|--remote".colorize.red}"
        error "See #{"'crux kube ysplit --help'".colorize.blue.bold} for more help \n"
      end

      unless options.has?("file") || options.has?("remote")
        error "Missing required option:"
        error "\t#{"-f|--file".colorize.red} or #{"-r|--remote".colorize.red}"
        error "See #{"'crux kube ysplit --help'".colorize.blue.bold} for more help \n"
      end
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      if options.has?("file")
      elsif options.has?("remote")
        url = URI.parse options.get("remote").as_s
        validate_yaml_url(url)
      end
    rescue ex : YSplitError
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

    # Custom exceptions - what kind of failures do we expect to see?
    # Base domain exception
    class YSplitError < Exception
    end

    # Any reason to use this over the YAML::ParseException??
    class YAMLValidationError < YSplitError
    end

    # When the YAML doc is valid but not a K8s object
    class K8sDocumentError < YSplitError
    end

    struct K8sDocument
    end

    # Custom methods - what actions to we have to take?

    # Validate that the user-provided URL is an HTTP endpoint and likely contains YAML
    def validate_yaml_url(url : URI) : String
      valid_scheme : Regex = /^https?$/
      if url.scheme.try { |scheme| valid_scheme.matches?(scheme) } &&
         url.host &&
         url.path.split(".").last.downcase == "yaml"
        url.to_s
      else
        raise YSplitError.new("'#{url.to_s.colorize.red}' is not a valid url")
      end
    end

    # Retrieve local yaml content
    def read_local_yaml
    end

    # Process yaml content
    def process_yaml
    end

    # Write procesed yaml to individual files
    def write_yaml
    end
  end
end
