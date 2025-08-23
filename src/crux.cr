require "cling"
require "colorize"
require "yaml"

require "./commands/base"
Colorize.on_tty_only!

module Crux
  class Main < Commands::Base
    def setup : Nil
      @name = "crux"
      @description = <<-DESC
      The CLI tool at the crux of your day to day developer experience.
      DESC

      add_usage "crux <command> <subcommand> [options] <arguments>"

      # TODO register commands here with 'add_command'
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # Show help menu by default if no other commands passed
      stdout.puts help_template
    end
  end
end
