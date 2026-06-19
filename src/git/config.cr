require "kyaml"
require "yaml"

module Crux::Git
  # Raised for any configuration problem: missing files, malformed kyaml, or
  # references that do not resolve (e.g. a repo pointing at an unknown profile).
  class ConfigError < Exception
  end

  # Resolves the directory crux uses for its git-namespace configuration.
  #
  # Honors $CRUX_CONFIG_HOME for tests and power users, then $XDG_CONFIG_HOME,
  # finally falling back to ~/.config. The git configs live under `crux/git`.
  def self.config_dir : String
    if override = ENV["CRUX_CONFIG_HOME"]?
      return override
    end

    base = ENV["XDG_CONFIG_HOME"]? || File.join(Path.home.to_s, ".config")
    File.join(base, "crux", "git")
  end

  # Absolute path to the profiles config file.
  def self.profiles_path : String
    File.join(config_dir, "profiles.kyaml")
  end

  # Absolute path to the batch repo-list config file.
  def self.batch_path : String
    File.join(config_dir, "batch.kyaml")
  end

  # Commit identity (name/email) associated with a profile.
  struct Identity
    include KYAML::Serializable

    getter name : String
    getter email : String
  end

  # A single git profile: the per-context identity a machine uses to talk to a
  # git host. Mirrors the "two GitHub accounts on one machine" pattern.
  struct Profile
    include KYAML::Serializable

    getter name : String

    @[KYAML::Field(key: "sshKey")]
    getter ssh_key : String?

    @[KYAML::Field(key: "sshHostAlias")]
    getter ssh_host_alias : String?

    @[KYAML::Field(key: "signingKey")]
    getter signing_key : String?

    getter user : Identity?

    # Builds the environment overrides git should run with for this profile.
    #
    # When the profile declares an ssh key, GIT_SSH_COMMAND pins transport to
    # that key with IdentitiesOnly so an unrelated agent key cannot shadow it.
    # Returns nil when the profile needs no special environment.
    def git_env : Hash(String, String)?
      key = ssh_key
      return nil unless key

      expanded = File.expand_path(key)
      {"GIT_SSH_COMMAND" => "ssh -i #{expanded} -o IdentitiesOnly=yes"}
    end
  end

  # Top-level profiles document: the set of profiles configured on this machine.
  struct ProfilesConfig
    include KYAML::Serializable

    getter profiles : Array(Profile)

    # Loads and parses the profiles file at `path`.
    #
    # Raises ConfigError on a missing file or malformed kyaml.
    def self.load(path : String = Crux::Git.profiles_path) : ProfilesConfig
      raise ConfigError.new("profiles config not found: #{path}") unless File.exists?(path)
      from_kyaml(File.read(path))
    rescue ex : KYAML::ParseError | YAML::ParseException
      raise ConfigError.new("invalid profiles config '#{path}': #{ex.message}")
    end

    # Returns the profile named `name`, or nil when no such profile exists.
    def find(name : String) : Profile?
      profiles.find { |profile| profile.name == name }
    end
  end

  # A repository tracked by the batch list, bound to a named profile.
  struct RepoEntry
    include KYAML::Serializable

    getter url : String
    getter profile : String

    # Optional checkout directory relative to the batch root. When omitted the
    # directory name is derived from the repository URL.
    getter path : String?

    # Returns the directory name this repo clones into, relative to the root.
    # Derives "<name>" from a "<...>/<name>.git" style URL when `path` is unset.
    def dir_name : String
      explicit = path
      return explicit if explicit && !explicit.empty?

      segment = url.split('/').last
      segment = segment[0...-4] if segment.ends_with?(".git")
      segment
    end
  end

  # Top-level batch document: where repos live locally and the tracked list.
  struct BatchConfig
    include KYAML::Serializable

    # Base directory under which all batch repos are cloned/pulled.
    getter root : String

    getter repos : Array(RepoEntry)

    # Loads and parses the batch file at `path`.
    #
    # Raises ConfigError on a missing file or malformed kyaml.
    def self.load(path : String = Crux::Git.batch_path) : BatchConfig
      raise ConfigError.new("batch config not found: #{path}") unless File.exists?(path)
      from_kyaml(File.read(path))
    rescue ex : KYAML::ParseError | YAML::ParseException
      raise ConfigError.new("invalid batch config '#{path}': #{ex.message}")
    end

    # Expands the configured root to an absolute path (resolving ~ and relatives).
    def expanded_root : String
      File.expand_path(root)
    end
  end

  # Ticket-prefix policy for `crux git commit`, hydrated from per-repo config.
  #
  # This is what lets the same command serve both work repos (ticket required)
  # and personal repos (no ticket) without the user remembering which mode the
  # current repository is in.
  struct TicketConfig
    include KYAML::Serializable

    # Whether a ticket reference must be supplied for every commit.
    getter required : Bool = false

    # Optional regex the ticket must match (e.g. "[A-Z]+-\\d+").
    getter pattern : String?

    # Whether to validate the ticket against `pattern`. Returns true and the
    # ticket unchanged when no pattern is configured.
    def valid?(ticket : String) : Bool
      pat = pattern
      return true unless pat
      !!Regex.new(pat).match(ticket)
    end
  end

  # Per-repository commit configuration. Lives at the repo root (default
  # `.crux.kyaml`) and is optional: an absent file yields permissive defaults.
  struct CommitConfig
    include KYAML::Serializable

    getter ticket : TicketConfig?

    # Optional override of the allowed conventional-commit types.
    getter types : Array(String)?

    # Optional list of suggested scopes surfaced during the interactive prompt.
    getter scopes : Array(String)?

    # Explicit initializer so callers can build permissive defaults via `.new`
    # (KYAML::Serializable only generates the node-based initializer).
    def initialize(@ticket : TicketConfig? = nil, @types : Array(String)? = nil, @scopes : Array(String)? = nil)
    end

    # Conventional file name crux looks for at the repository root.
    FILE_NAME = ".crux.kyaml"

    # Loads commit config for the repository rooted at `repo_root`.
    #
    # Returns permissive defaults when no config file is present so the command
    # works out of the box in unconfigured (personal) repositories.
    def self.load(repo_root : String) : CommitConfig
      path = File.join(repo_root, FILE_NAME)
      return CommitConfig.new unless File.exists?(path)

      from_kyaml(File.read(path))
    rescue ex : KYAML::ParseError | YAML::ParseException
      raise ConfigError.new("invalid commit config '#{File.join(repo_root, FILE_NAME)}': #{ex.message}")
    end

    # Returns the configured allowed types, falling back to the conventional set.
    def allowed_types : Array(String)
      types || ConventionalCommit::DEFAULT_TYPES
    end

    # Returns true when a ticket reference is mandatory for this repository.
    def ticket_required? : Bool
      !!ticket.try(&.required)
    end
  end
end
