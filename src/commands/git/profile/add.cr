module Crux::Commands
  class ProfileAdd < Profile
    include Prompt

    property keygen : Crux::Git::KeyGen
    property writer : Crux::Git::ProfileWriter

    # Injectable collaborators: a fake KeyGen and a temp-dir-backed writer let
    # tests drive the whole flow without ssh-keygen or touching real dotfiles.
    def initialize(
      @keygen : Crux::Git::KeyGen = Crux::Git::RealKeyGen.new,
      @writer : Crux::Git::ProfileWriter = Crux::Git::ProfileWriter.new,
    )
      super()
    end

    def setup : Nil
      @name = "add"
      @summary = "interactively create and wire up a new git profile"
      @description = <<-DESC
        Walks you through creating a git profile: generates (or reuses) an ssh
        key, adds a Host alias to ~/.ssh/config, writes a gitconfig signing
        fragment, and records the profile in #{Crux::Git.profiles_path}.

        Every change is summarized and confirmed before anything is written.
        DESC

      add_usage "crux git profile add [options]"

      add_option 'y', "yes", description: "skip the confirmation prompt before writing"
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      skip_confirm = options.has?("yes")

      name = prompt_name
      return if name.empty?

      host = ask("Git host", default: "github.com")
      host_label = host.split('.').first
      host_alias = ask("SSH host alias", default: "#{host_label}-#{name}")
      default_key = File.join(Path.home.to_s, ".ssh", "id_#{name}_ed25519")
      key_path = File.expand_path(ask("SSH key path", default: default_key), home: true)

      identity = prompt_identity
      signing = confirm?("Enable SSH commit signing?", default: true)
      signing_key = signing ? "#{key_path}.pub" : nil

      profile = Crux::Git::Profile.new(
        name: name,
        ssh_key: key_path,
        ssh_host_alias: host_alias,
        signing_key: signing_key,
        user: identity,
      )

      key_exists = File.exists?(key_path)
      print_summary(profile, host, key_exists)

      unless skip_confirm || confirm?("Apply these changes?")
        info "Aborted."
        return
      end

      apply(profile, host, key_exists, identity)
    rescue ex : Crux::Git::ConfigError
      error "#{"Profile error:".colorize.bold}"
      error "\t#{ex.message}"
      exit_program 1
    end

    def post_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    # Prompts for the profile name, looping until non-empty, and confirms an
    # overwrite when the name already exists. Returns "" to signal abort.
    private def prompt_name : String
      loop do
        name = ask("Profile name")
        if name.empty?
          warn "A profile name is required."
          next
        end

        if @writer.profile_exists?(name)
          return name if confirm?("Profile '#{name}' already exists. Overwrite it?", default: false)
          return ""
        end

        return name
      end
    end

    # Prompts for the commit identity. Includes it only when both name and email
    # are given; warns and drops it if exactly one is supplied.
    private def prompt_identity : Crux::Git::Identity?
      commit_name = ask("Commit name (optional)")
      commit_email = ask("Commit email (optional)")

      return Crux::Git::Identity.new(commit_name, commit_email) if !commit_name.empty? && !commit_email.empty?

      if commit_name.empty? != commit_email.empty?
        warn "Commit name and email must both be set; skipping commit identity."
      end
      nil
    end

    # Prints the set of changes that will be made, before asking to apply them.
    private def print_summary(profile : Crux::Git::Profile, host : String, key_exists : Bool) : Nil
      stdout << '\n' << "Planned changes:".colorize.blue.bold << '\n'

      key_note = key_exists ? "reuse existing key" : "generate new ed25519 key"
      summary_line "ssh key", "#{profile.ssh_key} (#{key_note})"
      summary_line "ssh config", "Host #{profile.ssh_host_alias} -> #{host} (#{@writer.ssh_config_path})"
      if profile.signing_key
        summary_line "git signing", @writer.fragment_path(profile.name)
      end
      summary_line "profile store", @writer.profiles_path
      stdout << '\n'
    end

    private def summary_line(label : String, value : String) : Nil
      stdout << "  " << "#{label}:".colorize.cyan << ' ' << value << '\n'
    end

    # Executes the confirmed writes in order, reporting each step.
    private def apply(profile : Crux::Git::Profile, host : String, key_exists : Bool, identity : Crux::Git::Identity?) : Nil
      ensure_key(profile, key_exists, identity)

      if @writer.append_ssh_config(profile, host)
        info "Added Host #{profile.ssh_host_alias} to #{@writer.ssh_config_path}"
      else
        info "Host #{profile.ssh_host_alias} already present in #{@writer.ssh_config_path}; left unchanged"
      end

      if profile.signing_key
        fragment = @writer.write_fragment(profile)
        info "Wrote git signing fragment to #{fragment}"
      end

      @writer.save_profile(profile)
      info "#{"Saved profile".colorize.bold.green} '#{profile.name}' to #{@writer.profiles_path}"

      print_next_steps(profile)
    end

    # Generates the ssh key when absent, or reports reuse. Exits on failure.
    private def ensure_key(profile : Crux::Git::Profile, key_exists : Bool, identity : Crux::Git::Identity?) : Nil
      key_path = profile.ssh_key
      return unless key_path

      if key_exists
        info "Reusing existing key at #{key_path}"
        return
      end

      unless @keygen.available?
        error "'ssh-keygen' not found on PATH; cannot generate a key"
        error "Install openssh, or point the profile at an existing key"
        exit_program 1
      end

      Dir.mkdir_p(File.dirname(key_path), 0o700)
      email = identity.try(&.email)
      comment = email && !email.empty? ? email : profile.name
      result = @keygen.generate(key_path, comment)

      unless result.success?
        error "ssh-keygen failed:"
        error "\t#{result.error.strip}"
        exit_program 1
      end
      info "Generated ed25519 key at #{key_path}"
    end

    # Prints the manual follow-up steps crux can't safely do automatically.
    private def print_next_steps(profile : Crux::Git::Profile) : Nil
      stdout << '\n' << "Next steps:".colorize.blue.bold << '\n'
      if key = profile.ssh_key
        stdout << "  - Add the public key to your git host: " << "cat #{key}.pub".colorize.bold << '\n'
      end
      if profile.signing_key
        stdout << "  - Activate signing for a directory by adding to ~/.gitconfig:\n"
        stdout << "      [includeIf \"gitdir:~/path/to/repos/\"]\n"
        stdout << "          path = " << @writer.fragment_path(profile.name) << '\n'
      end
    end
  end
end
