module Crux::Commands
  # Override upstream Cling::Command with baseline command behaviors, options, and styles to be inherited by all crux commands.
  abstract class Base < Cling::Command
    # Patch upstream method to include these three options and behaviors to all commands by default
    def initialize
      super

      @inherit_options = true
      @debug = false
      add_option 'h', "help", description: "show help information"
      add_option "debug", description: "print debug information"
      add_option "no-color", description: "disable color codes"
    end

    # Returns the help template for this command.
    # Overrides the upstream Cling::Command.help_template method with help text colors, consistent output spacing, and structure.
    # Only partially implements Cling::Formatter, so look at upstream for any missing functionality.
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

    # Override the upstream cling pre_run method
    # Intercept and apply default behavior for globally available options
    def pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      @debug = true if options.has? "debug"
      Colorize.enabled = false if options.has? "no-color"

      if options.has? "help"
        stdout.puts help_template
        exit_program 0
      end
    end

    def debug(data : _) : Nil
      return unless @debug
      stdout << "(#) ".colorize.blue << data << '\n'
    end

    def info(data : _) : Nil
      stdout << "(i) ".colorize.green << data << '\n'
    end

    def warn(data : _) : Nil
      stdout << "(!) ".colorize.yellow << data << '\n'
    end

    def error(data : _) : Nil
      stdout << "(!!) ".colorize.red << data << '\n'
    end

    # Override and extend upstream cling on_error method
    # Use the crux-specific log formatting methods, provide more useful error help, and implement debug flag support
    def on_error(ex : Exception)
      case ex
      # handle cling exceptions here
      when Cling::CommandError
        help_command = %(#{full_command_path} --help).colorize.blue.bold
        error ex
        error "See '#{help_command}' for more help"
        # and I guess any other unexpected exceptions too
      else
        error "Unexpected exception:"
        error ex
      end

      if @debug
        # handle failure in case ex.backtrace is nil and not provided
        if backtrace = ex.backtrace
          debug "Loading stack trace..."
          backtrace.each { |line| debug " " + line }
        else
          debug "No stack trace available"
        end
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

    # A hook method for when the command receives missing arguments during execution.
    # Overriddes Cling::Command.on_missing_arguments with custom formatting
    def on_missing_arguments(args : Array(String))
      help_command = "#{full_command_path} --help".colorize.blue.bold

      error "Missing required argument#{"s" if args.size > 1}:"
      error " #{args.join(", ")}"
      error "See '#{help_command}' for more help"
      exit_program
    end

    # A hook method for when the command receives unknown arguments during execution.
    # Overriddes Cling::Command.on_unknown_arguments with custom formatting
    def on_unknown_arguments(args : Array(String))
      help_command = %(#{full_command_path}--help).colorize.blue.bold

      error "Unexpected argument#{"s" if args.size > 1} for this command:"
      error "\t#{args.join(", ")}".colorize.red
      error "See '#{help_command}' for more information"
      exit_program
    end

    # A hook method for when the command receives unknown options during execution.
    # Overriddes Cling::Command.on_unknown_options with custom formatting
    def on_unknown_options(options : Array(String))
      help_command = %(#{full_command_path} --help).colorize.blue.bold

      error "Unexpected option#{"s" if options.size > 1} for this command:"
      error "\t#{options.join ", "}".colorize.red
      error "See '#{help_command}' for more information"
      exit_program
      # raise Cling::CommandError.new
    end
  end
end
