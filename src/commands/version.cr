module Crux::Commands
  class Version < Base
    def setup : Nil
      @debug = true
      @name = "version"
      @summary = "show tool version"
      @description = "Shows the version information for Crux."
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      stdout << "crux version: #{Crux::VERSION} "
      stdout << "[#{Crux::BUILD_HASH}] "
      stdout << "(#{Crux::BUILD_DATE})\n"
    end
  end
end
