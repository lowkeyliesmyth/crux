module Crux::Commands
  class Ysplit < Base
    def setup : Nil
      @name = "ysplit"
      @summary = "split multi-doc YAML manifests"
      @description = "Split multi-document Kubernetes YAML manifests into separate files."

      # TODO: add add_usage entry
      add_usage "ysplit [options]"

      # TODO: add add_arguments entries

      # TODO: add add_options entries
      add_option 'f', "file", description: "local path to source YAML manifest"
      add_option 'n', "name", description: "project name prefixed to generated output files"
      add_option 'o', "output", description: "output directory for split files"
      add_option 'r', "remote", description: "HTTP URL source to fetch remote YAML manifest"
    end

    # TODO: add any mutually-exclusive option logic in pre_run
    def pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    # TODO: add actual working logic in here
    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    def post_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end
  end
end
