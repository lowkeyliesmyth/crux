module Crux::Commands
  class Commit < Git
    property git : Crux::Git::Runner

    # Accepts an injectable runner so tests can drive the flow with a fake git
    # and a scripted stdin instead of touching a real repository.
    def initialize(@git : Crux::Git::Runner = Crux::Git::RealGit.new)
      super()
    end

    def setup : Nil
      @name = "commit"
      @summary = "interactive conventional-commit generator"
      @description = <<-DESC
        Walks you through a conventional commit (type, scope, subject, body) and
        commits the staged changes with a properly formatted message.

        Adapts to the current repository: if a #{Crux::Git::CommitConfig::FILE_NAME}
        at the repo root requires a ticket prefix, you are prompted for one and it
        is validated; otherwise the ticket step is skipped.
        DESC

      add_usage "crux git commit [options]"
      add_usage ""
      add_usage "EXAMPLES"
      add_usage "crux git commit"
      add_usage "crux git commit -a"

      add_option 'a', "all", description: "stage all tracked, modified files before committing"
      add_option 'y', "yes", description: "skip the final confirmation prompt"
    end

    def command_pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      unless @git.installed?
        error "'git' executable not found on PATH"
        error "Install git and try again"
        exit_program 1
      end
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      stage_all = options.has?("all")
      skip_confirm = options.has?("yes")

      repo_root = @git.toplevel(Dir.current)
      unless repo_root
        error "not a git repository (or any parent directory)"
        exit_program 1
      end

      config = Crux::Git::CommitConfig.load(repo_root)

      unless stage_all || @git.staged_changes?(repo_root)
        error "no staged changes to commit"
        error "Stage changes first, or pass #{"-a|--all".colorize.red} to stage tracked files"
        exit_program 1
      end

      commit = build_commit(config)
      commit.validate!(config.allowed_types)
      message = commit.render

      stdout << '\n' << "Commit message preview:".colorize.blue.bold << '\n'
      message.each_line { |line| stdout << "    " << line.colorize.light_magenta << '\n' }
      stdout << '\n'

      unless skip_confirm || confirm?("Create this commit?")
        info "Aborted."
        return
      end

      result = @git.commit(repo_root, message, stage_all)
      if result.success?
        info "#{"Committed:".colorize.bold.green} #{commit.header_line}"
      else
        error "git commit failed:"
        error "\t#{result.error.strip}"
        exit_program 1
      end
    rescue ex : Crux::Git::ConfigError | Crux::Git::CommitError
      error "#{"Commit error:".colorize.bold}"
      error "\t#{ex.message}"
      exit_program 1
    end

    def post_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    # Drives the interactive prompts and assembles a ConventionalCommit.
    private def build_commit(config : Crux::Git::CommitConfig) : Crux::Git::ConventionalCommit
      type = prompt_type(config.allowed_types)
      scope = prompt_scope(config.scopes)
      ticket = prompt_ticket(config)
      subject = prompt_subject
      body = prompt_body
      breaking, breaking_description = prompt_breaking

      Crux::Git::ConventionalCommit.new(
        type: type,
        subject: subject,
        scope: scope,
        body: body,
        ticket: ticket,
        breaking: breaking,
        breaking_description: breaking_description,
      )
    end

    # Prompts for a commit type, accepting either the list number or the name.
    private def prompt_type(types : Array(String)) : String
      stdout << "Select a commit type:".colorize.blue.bold << '\n'
      types.each_with_index do |type, index|
        stdout << "  #{index + 1}) ".colorize.green << type << '\n'
      end

      loop do
        choice = ask("Type [1-#{types.size} or name]")
        if choice.empty?
          warn "A commit type is required."
          next
        end

        if (number = choice.to_i?) && (1..types.size).includes?(number)
          return types[number - 1]
        end

        return choice if types.includes?(choice)
        warn "Not a valid type. Enter a number 1-#{types.size} or a listed name."
      end
    end

    # Prompts for an optional scope, surfacing any configured suggestions.
    private def prompt_scope(scopes : Array(String)?) : String?
      if suggestions = scopes
        stdout << "Suggested scopes: ".colorize.blue << suggestions.join(", ") << '\n' unless suggestions.empty?
      end
      value = ask("Scope (optional)")
      value.empty? ? nil : value
    end

    # Prompts for a ticket reference, enforcing repo policy and pattern.
    private def prompt_ticket(config : Crux::Git::CommitConfig) : String?
      ticket_config = config.ticket
      required = config.ticket_required?
      label = required ? "Ticket (required)" : "Ticket (optional)"

      loop do
        value = ask(label)

        if value.empty?
          return nil unless required
          warn "This repository requires a ticket reference."
          next
        end

        if ticket_config && !ticket_config.valid?(value)
          warn "Ticket '#{value}' does not match the required pattern #{ticket_config.pattern}."
          next
        end

        return value
      end
    end

    # Prompts for the subject line, looping until a non-empty value is given.
    private def prompt_subject : String
      loop do
        value = ask("Subject")
        return value unless value.empty?
        warn "A subject is required."
      end
    end

    # Prompts for an optional multi-line body, terminated by a blank line.
    private def prompt_body : String?
      stdout << "Body (optional, finish with an empty line):".colorize.blue << '\n'
      lines = [] of String
      loop do
        line = stdin.gets
        break if line.nil? || line.empty?
        lines << line
      end
      lines.empty? ? nil : lines.join('\n')
    end

    # Prompts whether the change is breaking and, if so, for a description.
    private def prompt_breaking : {Bool, String?}
      return {false, nil} unless confirm?("Is this a breaking change?", default: false)
      description = ask("Describe the breaking change (optional)")
      {true, description.empty? ? nil : description}
    end

    # Writes a prompt label and returns the trimmed user response (or "" on EOF).
    private def ask(label : String) : String
      stdout << label.colorize.cyan << ": "
      (stdin.gets || "").strip
    end

    # Yes/no prompt. Returns `default` on an empty answer or EOF.
    private def confirm?(label : String, default : Bool = true) : Bool
      hint = default ? "Y/n" : "y/N"
      stdout << label.colorize.cyan << " [#{hint}]: "
      answer = (stdin.gets || "").strip.downcase
      return default if answer.empty?
      answer.starts_with?('y')
    end
  end
end
