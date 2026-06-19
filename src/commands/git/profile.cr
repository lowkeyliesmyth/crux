module Crux::Commands
  class Profile < Git
    def setup : Nil
      @name = "profile"
      @summary = "manage per-context git profiles (identity, ssh, signing)"
      @description = <<-DESC
        Manage the git profiles configured on this machine: the per-context
        identity (ssh key, ssh host alias, signing key, commit name/email) used
        to interact with git hosts.

        Profiles are stored at #{Crux::Git.profiles_path} and are referenced by
        the batch repo list so each repository uses the right identity.
        DESC

      add_usage "crux git profile [subcommand] [arguments] [options]"

      add_command Commands::ProfileAdd.new
      add_command Commands::ProfileList.new
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # Container command just shows the help menu when called without a subcommand.
      stdout.puts help_template
    end
  end
end
