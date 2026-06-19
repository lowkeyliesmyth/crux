module Crux::Git
  # Persists git profiles and wires up the local machine for them.
  #
  # Owns the three write targets `profile add` touches: the profiles.kyaml
  # store, the user's ~/.ssh/config, and a per-profile gitconfig fragment. All
  # paths are injectable so the whole thing can be driven against temp dirs in
  # tests. Operations are idempotent where it matters (ssh aliases, profile
  # upserts) so re-running add is safe.
  class ProfileWriter
    getter profiles_path : String
    getter ssh_config_path : String
    getter fragment_dir : String

    def initialize(
      @profiles_path : String = Crux::Git.profiles_path,
      @ssh_config_path : String = File.join(Path.home.to_s, ".ssh", "config"),
      @fragment_dir : String = File.join(Crux::Git.config_dir, "profiles"),
    )
    end

    # Loads the existing profiles, or an empty set when no file exists yet.
    def load_profiles : ProfilesConfig
      File.exists?(@profiles_path) ? ProfilesConfig.load(@profiles_path) : ProfilesConfig.new
    end

    # Returns true if a profile named `name` is already stored.
    def profile_exists?(name : String) : Bool
      !load_profiles.find(name).nil?
    end

    # Upserts `profile` (replacing any existing one of the same name) and writes
    # the profiles.kyaml file, creating its directory as needed.
    def save_profile(profile : Profile) : Nil
      existing = load_profiles.profiles.reject { |entry| entry.name == profile.name }
      updated = ProfilesConfig.new(existing + [profile])

      Dir.mkdir_p(File.dirname(@profiles_path))
      File.write(@profiles_path, updated.to_kyaml)
    end

    # Returns true if ~/.ssh/config already declares a `Host` block matching
    # `host_alias`, so we never append a duplicate entry.
    def ssh_alias_present?(host_alias : String) : Bool
      return false unless File.exists?(@ssh_config_path)

      File.read_lines(@ssh_config_path).any? do |line|
        tokens = line.strip.split
        tokens.size >= 2 && tokens[0].downcase == "host" && tokens[1..].includes?(host_alias)
      end
    end

    # Renders the ~/.ssh/config Host block for `profile` against `host`.
    def ssh_config_block(profile : Profile, host : String) : String
      String.build do |io|
        io << "# Managed by crux - git profile \"" << profile.name << "\"\n"
        io << "Host " << profile.ssh_host_alias << '\n'
        io << "    HostName " << host << '\n'
        io << "    User git\n"
        io << "    IdentityFile " << profile.ssh_key << '\n'
        io << "    IdentitiesOnly yes\n"
      end
    end

    # Appends an ssh config block, ensuring blank-line separation from any
    # existing content. Returns false (no write) when the alias already exists.
    def append_ssh_config(profile : Profile, host : String) : Bool
      host_alias = profile.ssh_host_alias
      return false if host_alias && ssh_alias_present?(host_alias)

      Dir.mkdir_p(File.dirname(@ssh_config_path))
      block = ssh_config_block(profile, host)

      if File.exists?(@ssh_config_path) && !File.read(@ssh_config_path).strip.empty?
        existing = File.read(@ssh_config_path)
        separator = existing.ends_with?("\n") ? "\n" : "\n\n"
        File.write(@ssh_config_path, existing + separator + block)
      else
        File.write(@ssh_config_path, block)
      end

      true
    end

    # Absolute path of the per-profile gitconfig fragment.
    def fragment_path(name : String) : String
      File.join(@fragment_dir, "#{name}.gitconfig")
    end

    # Renders the gitconfig fragment: commit identity plus ssh-format signing
    # when the profile carries a signing key.
    def gitconfig_fragment(profile : Profile) : String
      String.build do |io|
        io << "# Managed by crux - git profile \"" << profile.name << "\"\n"

        if user = profile.user
          io << "[user]\n"
          io << "    name = " << user.name << '\n'
          io << "    email = " << user.email << '\n'
          if key = profile.signing_key
            io << "    signingkey = " << key << '\n'
          end
        end

        if profile.signing_key
          io << "[gpg]\n"
          io << "    format = ssh\n"
          io << "[commit]\n"
          io << "    gpgsign = true\n"
          io << "[tag]\n"
          io << "    gpgsign = true\n"
        end
      end
    end

    # Writes the gitconfig fragment file and returns its path.
    def write_fragment(profile : Profile) : String
      Dir.mkdir_p(@fragment_dir)
      path = fragment_path(profile.name)
      File.write(path, gitconfig_fragment(profile))
      path
    end
  end
end
