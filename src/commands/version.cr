module Crux::Commands
  class Version < Base
    def setup : Nil
      @name = "version"
      @summary = "show tool version"
      @description = "Shows the version information for Crux"

      add_usage "crux version"
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      stdout << "crux version: #{Crux::VERSION} "
      stdout << "[#{Crux::BUILD_HASH}] "
      stdout << "(#{Crux::BUILD_DATE})\n"
    end
  end
end
