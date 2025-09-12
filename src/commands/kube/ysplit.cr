module Crux::Commands
  class Ysplit < Base
    def setup : Nil
      @name = "ysplit"
      @summary = "split multi-doc YAML manifests into one file per object"
      @description = <<-DESC
        Splits multi-document Kubernetes YAML manifests into multiple separate local files.
        Outputs one valid YAML manifest file per detected K8s object.
        DESC

      add_usage "crux kube ysplit <target> [options]"
      add_argument "target", description: "path to save generated output files", required: true

      # TODO: add support for cleaning out target directory of existing files.
      # # Ensure that we add a prompt for confirmation by the user before executing.
      # add_option "clean", description: "clean out target directory by first removing all existing files; will prompt for confirmation"

      # TODO: add support for a --force option dependent on the --clean option, to override confirmation prompt.  Useful when crux is run in CI or other automation.
      # # either fail or silently ignore the command if not also paired with the 'clean' command
      # add_option "force", description: "DANGEROUS; overrides confirmation prompt of 'clean' command without "

      add_option 'f', "file", description: "the local path to source YAML mega-manifest", type: :single
      add_option 'o', "output", description: "the output directory for split files", type: :single
      add_option 'p', "prefix", description: "the project name prefix added to generated output files", type: :single
      add_option 'r', "remote", description: "the HTTP URL source to fetch remote YAML manifest", type: :single
    end

    def pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # TODO: validate that target arg is a valid filesystem path
      # FIXME: Why isn't this help option parsing getting inherited from the Base.pre_run method?
      # Probably some weird inheritance problem with registering the ysplit grandchild command in the child kube.cr instead of parent crux.cr
      if options.has? "help"
        stdout.puts help_template
        exit_program 0
      end

      if options.has?("file") && options.has?("remote")
        error "Error: #{"--file".colorize.blue} and #{"--remote".colorize.blue} options are mutually exclusive"
        error "See #{"'crux kube ysplit --help'".colorize.blue.bold} for more help \n"
      end
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    def post_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end
  end
end
