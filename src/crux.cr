require "cling"
require "colorize"
require "yaml"

require "./commands/base"
require "./commands/*"
require "./commands/kube/*"
Colorize.on_tty_only!

module Crux
  # Build metadata constants generated at compile time and consumed by the Version command
  VERSION    = "0.1.0"
  BUILD_DATE = {{ `date +%F`.stringify.chomp }}
  BUILD_HASH = {{ `git rev-parse HEAD`.stringify[0...8] }}

  class Main < Commands::Base
    def setup : Nil
      @name = "crux"
      @description = <<-DESC
        The CLI tool at the crux of your day to day developer experience.
        DESC

      add_usage "crux <command> <subcommand> [options] <arguments>"

      # TODO: register commands here with add_command
      add_command Commands::Version.new
      add_command Commands::Kube.new
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # Show help menu by default if no other commands are passed
      stdout.puts help_template
    end
  end
end
