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
      add_usage "crux kube ysplit ~/Desktop -r https://remote.url/somefiles.yaml"

      # TODO: allow outdir to be optional, default to CWD
      add_argument "outdir", description: "path to save generated output files", required: true

      # TODO: add support for cleaning out target directory of existing files.
      # # Ensure that we add a prompt for confirmation by the user before executing.
      # add_option "clean", description: "clean out target directory by first removing all existing files; will prompt for confirmation"

      # TODO: add support for a --force option dependent on the --clean option, to override confirmation prompt.  Useful when crux is run in CI or other automation.
      # # either fail or silently ignore the command if not also paired with the 'clean' command
      # add_option "force", description: "DANGEROUS; overrides confirmation prompt of 'clean' command without "

      add_option 'f', "file", description: "the local path to a source YAML mega-manifest file", type: :single
      add_option 'p', "prefix", description: "a custom prefix added to each output filename", type: :single
      add_option 'r', "remote", description: "the HTTP/S URL to fetch a remote YAML manifest from", type: :single
    end

    def pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # TODO: Sanitize user input for prefix option
      # TODO: validate that user provided outdir arg is a valid filesystem path
      # TODO: validate that user provided file is present
      # FIXME: Why isn't this help option parsing getting inherited from the Base.pre_run method? And --debug and --no-color options too!
      # Probably some weird inheritance problem with registering the ysplit grandchild command in the child kube.cr instead of parent crux.cr
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
        # TODO: Remote, present for DEBUGGING
        validate_yaml_url(url)
      end
    rescue ex : YAMLSplitterError
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
    class YAMLSplitterError < Exception
    end

    # Any reason to use this over the YAML::ParseException??
    class YAMLValidationError < YAMLSplitterError
    end

    # When the YAML doc is valid but not a K8s object
    class K8sDocumentError < YAMLSplitterError
    end

    # Custom methods - what actions to we have to take?

    # Validates that the user-provided URL is an HTTP endpoint and likely contains YAML
    private def validate_yaml_url(url_arg : URI) : String
      valid_scheme : Regex = /https?/
      if url_arg.scheme.try { |scheme| valid_scheme.matches?(scheme) } &&
         url_arg.host &&
         url_arg.path.split(".").last.downcase == "yaml"
        url_arg.to_s
      else
        raise YAMLSplitterError.new("'#{url_arg.to_s.colorize.red}' is not a valid url")
      end
    end

    # Retrieves the remote yaml content
    private def read_remote_yaml(remote_url : URI) : Array(YAML::Any)
      debug "URL: #{url}"
      validate_yaml_url(remote_url)
      info "Retrieving: #{url.path.split("/").last}"
      # TODO: YOU ARE HERE: Implement remote yaml retrieval logic
    end

    private def read_local_yaml
    end

    private def process_yaml
    end

    private def write_yaml
    end
  end
end
