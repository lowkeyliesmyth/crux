module Crux::Commands::Global
  # Cling calls this framework-visible `pre_run` hook. `Global` owns that hook inside crux and injects a per-command behavior hook to ensure consistent behavior across commands.
  def pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    @debug = true if options.has? "debug"
    Colorize.enabled = false if options.has? "no-color"
    if options.has? "help"
      stdout.puts help_template
      exit_program 0
    end
    command_pre_run(arguments, options)
  end

  # Subclass commands override _THIS_ method with their per-command checks.
  def command_pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
  end
end
