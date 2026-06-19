module Crux::Commands
  class Git < Base
    def setup : Nil
      @name = "git"
      @summary = "git workflow utilities"
      @description = <<-DESC
        Opinionated helpers for day-to-day git workflows.

        Encodes conventional-commit and multi-repo conventions as defaults so
        common flows are faster than remembering the underlying git invocations.
        DESC

      add_usage "crux git [subcommand] [arguments] [options]"

      add_command Commands::Commit.new
      add_command Commands::Profile.new
      add_command Commands::Batch.new
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # Container command just shows the help menu when called without a subcommand.
      stdout.puts help_template
    end
  end
end
