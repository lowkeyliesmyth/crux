module Crux::Commands
  class ProfileList < Profile
    def setup : Nil
      @name = "list"
      @summary = "list the git profiles configured on this machine"
      @description = "Lists the git profiles stored at #{Crux::Git.profiles_path}."

      add_usage "crux git profile list"
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      unless File.exists?(Crux::Git.profiles_path)
        info "No profiles configured yet. Create one with #{"crux git profile add".colorize.blue.bold}"
        return
      end

      config = Crux::Git::ProfilesConfig.load
      if config.profiles.empty?
        info "No profiles configured yet. Create one with #{"crux git profile add".colorize.blue.bold}"
        return
      end

      info "#{config.profiles.size} profile#{"s" if config.profiles.size != 1} at #{Crux::Git.profiles_path}"
      config.profiles.each { |profile| render(profile) }
    rescue ex : Crux::Git::ConfigError
      error "#{"Config error:".colorize.bold}"
      error "\t#{ex.message}"
      exit_program 1
    end

    def post_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    # Prints one profile as an indented block of its configured fields.
    private def render(profile : Crux::Git::Profile) : Nil
      stdout << '\n' << "* ".colorize.green << profile.name.colorize.bold << '\n'
      field("host alias", profile.ssh_host_alias)
      field("ssh key", profile.ssh_key)
      field("signing key", profile.signing_key)
      if user = profile.user
        field("commit name", user.name)
        field("commit email", user.email)
      end
    end

    # Prints a single "label: value" line, skipping unset values.
    private def field(label : String, value : String?) : Nil
      return unless value
      stdout << "    " << "#{label}:".colorize.cyan << ' ' << value << '\n'
    end
  end
end
