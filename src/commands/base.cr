module Crux::Commands
  # Set some baseline behaviors, options, and styles
  abstract class Base < Cling::Command
    # Add these three options to all commands by default
    def initialize
      super

      @inherit_options = true
      @debug = false
      add_option "debug", description: "print debug information"
      add_option "no-color", description: "disable color codes"
      add_option 'h', "help", description: "show help information"
    end

    # Override the upstream cling help_template method
    # Let's dress up these help text colors, structure it, and ensure it has consistent spacing
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

    # TODO: Improve these logging methods later. Look to charmbracelet/log for inspiration on expanding helper functionality and visualizations
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
        error ex
        error "See '#{"crux --help".colorize.blue}' for more help"
        # and I guess any other unexpected exceptions too
      else
        error "Unexpected exception:"
        error ex
      end

      if @debug
        # handle failure in case ex.backtrace is nil
        if backtrace = ex.backtrace
          debug "Loading stack trace..."
          backtrace.each { |line| debug " " + line }
        else
          debug "No stack trace available"
        end
      end

      exit_program
    end

    # Override upstream cling on_missing_arguments method
    # Enrich output with crux-specific log methods and help guidance
    def on_missing_arguments(args : Array(String))
      help_command = "crux #{self.name} --help".colorize.blue.bold

      error "Missing required argument#{"s" if args.size > 1}:"
      error " #{args.join(", ")}"
      error "See '#{help_command}' for more help"
      exit_program
    end

    # Override upstream cling on_unknown_arguments method
    def on_unknown_arguments(args : Array(String))
    end
  end
end
