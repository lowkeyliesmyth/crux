module Crux::Commands
  class Kube < Base
    def setup : Nil
      @name = "kube"
      @summary = "kubernetes utilities"
      @description = "Collection of utilities for working with kubernetes manifests and resources."

      add_usage "crux kube [subcommand] [arguments] [options]"

      add_command Commands::Helmsplit.new
      add_command Commands::Ysplit.new
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # Container command just shows help menu when called without any subcommands
      stdout.puts help_template
    end
  end
end
