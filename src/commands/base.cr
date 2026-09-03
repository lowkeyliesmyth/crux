module Crux::Commands
  # Override upstream Cling::Command with baseline command behaviors, options, and styles to be inherited by all crux commands.
  abstract class Base < Cling::Command
    include Global

    # Patch upstream method to include these three options and behaviors to all commands by default
    def initialize
      super

      @inherit_options = true
      add_option 'h', "help", description: "show help information"
      add_option "debug", description: "print debug information"
      add_option "no-color", description: "disable color codes"
    end

    # Returns the help template for this command.
    # Overrides the upstream `Cling::Command.help_template` method with help text colors, consistent output spacing, and structure.
    # Only partially implements `Cling::Formatter`, so look at upstream for any missing functionality.
    def help_template : String
      String.build do |io|
        io << "Usage".upcase.colorize.blue.bold << '\n'
        @usage.each do |use|
          io << "\t " << use.colorize.light_magenta << '\n'
        end
        io << '\n'

        unless @children.empty?
          io << "Commands".upcase.colorize.blue.bold << '\n'
          # Enumerate all registered commands  and adjust spacing of command help text based on the longest command name string
          max_width = 4 + @children.keys.max_of(&.size)

          @children.each do |name, command|
            io << "* " << name.colorize.bold
            if summary = command.summary
              io << " " * (max_width - name.size)
              io << summary
            end
            io << '\n'
          end
          io << '\n'
        end

        unless @arguments.empty?
          io << "Arguments".upcase.colorize.blue.bold << '\n'
          max_width = 4 + @arguments.each.max_of { |name, _| name.size }
          @arguments.each do |name, arg|
            io << name.colorize.bold.cyan
            if description = arg.description
              io << " " * (max_width - name.size)
              io << description
              io << " (required)".colorize.cyan if arg.required?
              io << '\n'
            end
          end
          io << '\n'
          io << '\n'
        end

        io << "Options".upcase.colorize.blue.bold << '\n'
        max_width = 4 + @options.each.max_of { |name, opt| name.size + (opt.short ? 2 : 0) }

        # Align spacing, even with optional short options
        @options.each do |name, opt|
          if short = opt.short
            io << '-'.colorize.green << short.colorize.green << ", "
          end
          io << "--".colorize.green << name.colorize.green

          if description = opt.description
            name_width = name.size + (opt.short ? 4 : 0)
            io << " " * (max_width - name_width)
            io << description
          end
          io << '\n'
        end
        io << '\n'

        io << "Description".upcase.colorize.blue.bold << '\n'
        io << @description
      end
    end

    # Lazily instantiate a new `Etch::Logger`, or reference the existing instance if it already exists.
    protected def logger : Etch::Logger
      @logger ||= Etch::Logger.new(stdout)
    end

    # Configure the logger's debug and color profile based on the given cling command's constructed *options*.
    protected def configure_logger(options : Cling::Options) : Nil
      logger.output = stdout
      logger.level = options.has?("debug") ? Etch::Level::Debug : Etch::Level::Info
      logger.color_profile = Foundation::Profile::Ascii if options.has?("no-color")
    end

    # Emits a debug-level *message* with the given named k=v *fields* as structured data.
    def debug(message, **fields) : Nil
      logger.debug(message, **fields)
    end

    # Emits a debug-level *message* with the given *fields* k-v tuples as structured data.
    def debug(message, fields : Enumerable(Tuple(String, V))) : Nil forall V
      logger.debug(message, fields)
    end

    # Emits an info-level *message* with the given named k=v *fields* as structured data.
    def info(message, **fields) : Nil
      logger.info(message, **fields)
    end

    # Emits an info-level *message* with the given *fields* k-v tuples as structured data.
    def info(message, fields : Enumerable(Tuple(String, V))) : Nil forall V
      logger.info(message, fields)
    end

    # Emits a warn-level *message* with the given named k=v *fields* as structured data.
    def warn(message, **fields) : Nil
      logger.warn(message, **fields)
    end

    # Emits a warn-level *message* with the given *fields* k-v tuples as structured data.
    def warn(message, fields : Enumerable(Tuple(String, V))) : Nil forall V
      logger.warn(message, fields)
    end

    # Emits an error-level *message* with the given named k=v *fields* as structured data.
    def error(message, **fields) : Nil
      logger.error(message, **fields)
    end

    # Emits an error-level *message* with the given *fields* k-v tuples as structured data.
    def error(message, fields : Enumerable(Tuple(String, V))) : Nil forall V
      logger.error(message, fields)
    end

    # Handles backtrace emission and emitting user-facing error messsage for an *ex* exception raised during command execution.
    #
    # Overrides the upstream cling `on_error` method.
    def on_error(ex : Exception) : NoReturn
      case ex
      when Cling::CommandError
        error "Command failed",
          err: ex,
          help_command: help_command
      else
        error "Unexpected exception", err: ex

        backtrace = ex.backtrace
        debug "Unexpected exception context",
          backtrace: backtrace ? backtrace.join('\n') : "No stack trace available"
      end

      exit_program
    end

    # Build the full command path hierarchy from root to the current command
    private def full_command_path : String
      path_parts = [] of String
      current_command = self

      # Traverse up the command hierarchy and collect the command names
      while current_command
        if current_command.name == "main"
          path_parts << "crux"
        else
          path_parts << current_command.name
        end
        current_command = current_command.parent
      end

      # Construct the command stack string
      path_parts.reverse.join(" ")
    end

    # Hook fired when the command receives missing *args* during execution.
    #
    # Overrides upstream `on_missing_arguments` method.
    def on_missing_arguments(args : Array(String)) : NoReturn
      error "Missing required argument#{"s" if args.size > 1}",
        arguments: args.join(", "),
        help_command: help_command
      exit_program
    end

    # Hook fired when the command receives unknown *args* during execution.
    #
    # Overrides upstream `on_unknown_arguments` method.
    def on_unknown_arguments(args : Array(String)) : NoReturn
      error "Unexpected argument#{"s" if args.size > 1}",
        arguments: args.join(", "),
        help_command: help_command
      exit_program
    end

    # Hook fired when the command receives invalid options during execution that emits a *message*.
    #
    # Overrides upstream `on_invalid_option`
    def on_invalid_option(message : String) : NoReturn
      error "Invalid option",
        err: message,
        help_command: help_command
      exit_program
    end

    # Hook fired when the command receives missing *options* during execution.
    #
    # Overrides upstream `on_missing_option`.
    def on_missing_options(options : Array(String)) : NoReturn
      error "Missing required option#{"s" if options.size > 1}",
        options: options.join(", "),
        help_command: help_command
      exit_program
    end

    # Hook fired when the command receives unknown *options* during execution.
    #
    # Overrides upstream `on_unknown_options`.
    def on_unknown_options(options : Array(String))
      error "Unexpected options",
        options: options.join(", "),
        help_command: help_command
      exit_program
    end

    private def help_command : String
      "#{full_command_path} --help"
    end
  end
end
