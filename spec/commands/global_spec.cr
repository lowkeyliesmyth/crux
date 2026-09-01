require "../spec_helper"

# We want to ensure that global commands are both available to all sub/commands, and also that they are processed before local sub/commands options and args
private class GlobalOrderingFixture < Crux::Commands::Base
  class_property? command_pre_run_called : Bool = false

  def setup : Nil
    @name = "fixture"
    @description = "ordering test"
    add_usage "fixture"
  end

  def command_pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    self.class.command_pre_run_called = true
  end

  def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
  end
end

describe Crux::Commands::Global do
  context "with a new command" do
    it "processes global --help calls before invoking local command_pre_run commands" do
      GlobalOrderingFixture.command_pre_run_called = false
      cmd = GlobalOrderingFixture.new
      cmd.stdout = IO::Memory.new

      cmd.execute(["--help"])

      GlobalOrderingFixture.command_pre_run_called?.should be_false
    end
  end
end
