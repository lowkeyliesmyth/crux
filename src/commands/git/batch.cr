module Crux::Commands
  class Batch < Git
    def setup : Nil
      @name = "batch"
      @summary = "multi-repo operations over a managed repo list"
      @description = <<-DESC
        Operations across many repositories at once, driven by the batch list
        configured at #{Crux::Git.batch_path}.

        Each tracked repository is bound to a git profile from the profiles
        config so the right identity is used per repo.
        DESC

      add_usage "crux git batch [subcommand] [arguments] [options]"

      add_command Commands::Pull.new
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # Container command just shows the help menu when called without a subcommand.
      stdout.puts help_template
    end
  end
end
