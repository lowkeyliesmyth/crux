module Crux::Commands
  class Kube < Base
    def setup : Nil
      @name = "kube"
      @summary = "kubernetes utilities"
      @description = "Collection of utilities for working with kubernetes manifests and resources."

      add_usage "crux kube <subcommand> [options] <arguments>"

      # TODO: Register subcommands here with add_command
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # Container command just shows help menu when called without any subcommands
      stdout.puts help_template
    end
  end
end
