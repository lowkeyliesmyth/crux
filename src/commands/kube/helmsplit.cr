module Crux::Commands
  class Helmsplit < Kube
    class HelmsplitError < Exception
    end

    def setup : Nil
      @name = "helmsplit"
      @summary = "render a helm chart and split YAML manifests into one file per object"
      @description = <<-DESC
        Renders a Helm chart and splits the resulting multi-doc output into separate local files.

        Outputs one valid YAML manifest file per detected K8s object.
      DESC

      add_usage "crux kube helmsplit <outdir> <chart> [options]"
      add_usage ""
      add_usage "EXAMPLES"
      add_usage "crux kube helmsplit . jetstack/cert-manager -v 1.20"
      add_usage "crux kube helmsplit . jetstack/cert-manager -v 1.20 -f base.yaml -f prod.yaml -p cm"

      add_argument "outdir", description: "path to save generated output files", required: true
      add_argument "chart", description: "chart reference (repo/chart), or path to local chart", required: true

      add_option 'f', "file", description: "path to values file passed through to helm", type: :multiple, default: [] of String
      add_option 'p', "prefix", description: "custom prefix added to each output filename", type: :single
      add_option 'v', "version", description: "helm chart version to use", type: :single
    end

    def pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      if options.has? "help"
        stdout.puts help_template
        exit_program 0
      end
      @debug = true if options.has? "debug"
      Colorize.enabled = false if options.has? "no-color"

      # fail early if helm is not installed
      unless Process.find_executable("helm")
        error "'helm' executable not found on PATH"
        error "Install helm and try again"
        exit_program 1
      end
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end
  end
end
