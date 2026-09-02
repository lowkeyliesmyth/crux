require "../spec_helper"

private class BaseLoggerFixture < Crux::Commands::Base
  enum Action
    None
    Helpers
  end

  property action : Action = Action::None

  def setup : Nil
    @name = "fixture"
    @description = "base logger test fixture"
    add_usage "fixture"
  end

  def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    return unless action.helpers?

    debug "diagnostic", attempt: 1
    info "completed", written: 2
    warn "continued", skipped: 1
    error "failed", err: "boom"
  end

  def exposed_logger : Etch::Logger
    logger
  end
end

describe Crux::Commands::Base do
  it "lazily owns a single stable logger" do
    command = BaseLoggerFixture.new
    command.exposed_logger.should be(command.exposed_logger)
  end

  it "uses safe defaults before execution configuration" do
    output = IO::Memory.new
    command = BaseLoggerFixture.new
    command.stdout = output

    command.exposed_logger.info "before pre-run"

    output.to_s.should contain("INFO before pre-run")
    command.exposed_logger.level.should eq(Etch::Level::Info)
  end

  it "emits enabled level messages and structured fields to stdout" do
    output = IO::Memory.new
    errors = IO::Memory.new
    command = BaseLoggerFixture.new
    command.stdout = output
    command.stderr = errors
    command.action = BaseLoggerFixture::Action::Helpers

    command.execute([] of String)

    rendered = output.to_s
    rendered.should_not contain("diagnostic")
    rendered.should contain("INFO completed written=2")
    rendered.should contain("WARN continued skipped=1")
    rendered.should contain(%(ERRO failed err=boom))
  end

  it "enables debug reocrds with --debug" do
    output = IO::Memory.new
    command = BaseLoggerFixture.new
    command.stdout = output
    command.action = BaseLoggerFixture::Action::Helpers

    command.execute(["--debug"])

    output.to_s.should contain("DEBU diagnostic attempt=1")
  end

  it "resets debug level between executions" do
    debug_output = IO::Memory.new
    normal_output = IO::Memory.new
    command = BaseLoggerFixture.new
    command.action = BaseLoggerFixture::Action::Helpers

    command.stdout = debug_output
    command.execute(["--debug"])

    command.stdout = normal_output
    command.execute([] of String)

    debug_output.to_s.should contain("diagnostic")
    normal_output.to_s.should_not contain("diagnostic")
    command.exposed_logger.level.should eq(Etch::Level::Info)
  end

  it "forces unstyled profiles for the --no-color flag" do
    command = BaseLoggerFixture.new
    command.stdout = IO::Memory.new

    command.execute(["--no-color"])
    command.exposed_logger.color_profile.should eq(Foundation::Profile::Ascii)
  end
end
