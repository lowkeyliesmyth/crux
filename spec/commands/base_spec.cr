require "../spec_helper"

private class BaseLoggerFixture < Crux::Commands::Base
  enum Action
    None
    Helpers
    CommandError
    UnexpectedError
  end

  property action : Action = Action::None

  def setup : Nil
    @name = "fixture"
    @description = "base logger test fixture"
    add_usage "fixture"
  end

  def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    case action
    when .none?
    when .helpers?
      debug "diagnostic", attempt: 1
      info "completed", written: 2
      warn "continued", skipped: 1
      error "failed", err: "boom"
    when .command_error?
      raise Cling::CommandError.new("expected failure")
    when .unexpected_error?
      raise Exception.new("unexpected failure")
    end
  end

  def exposed_logger : Etch::Logger
    logger
  end
end

private class BaseValidationFixture < Crux::Commands::Base
  def setup : Nil
    @name = "fixtures"
    @description = "validation text fixture"
    add_usage "fixture <required_arg> --required-option"
    add_argument "required_arg",
      description: "This is a required arg", required: true
    add_option "required-option",
      description: "This is a required option",
      required: true,
      type: :none
    add_option "value",
      description: "Single response option",
      type: :single
  end

  def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
  end
end

describe Crux::Commands::Base do
  context "BaseLoggerFixture" do
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

    it "emits handled command errors as a single record" do
      output = IO::Memory.new
      errors = IO::Memory.new
      command = BaseLoggerFixture.new
      command.stdout = output
      command.stderr = errors
      command.action = BaseLoggerFixture::Action::CommandError

      status = command.execute([] of String)

      status.should eq(1)
      output.to_s.lines.size.should eq(1)
      output.to_s.should contain("ERRO Command failed")
      output.to_s.should contain(%(err="expected failure"))
      output.to_s.should contain(%(help_command="fixture --help"))
      errors.to_s.should be_empty
    end

    it "emits unexpected exceptions without debug backtraces by default" do
      output = IO::Memory.new
      command = BaseLoggerFixture.new
      command.stdout = output
      command.action = BaseLoggerFixture::Action::UnexpectedError

      status = command.execute([] of String)

      status.should eq(1)
      output.to_s.should contain("ERRO Unexpected exception")
      output.to_s.should_not contain("backtrace=")
    end

    it "emits unexpected-exception backtraces when debug mode is enabled " do
      output = IO::Memory.new
      command = BaseLoggerFixture.new
      command.stdout = output
      command.action = BaseLoggerFixture::Action::UnexpectedError

      status = command.execute(["--debug"])

      status.should eq(1)
      output.to_s.should contain("ERRO Unexpected exception ")
      output.to_s.should contain("DEBU Unexpected exception context")
      output.to_s.should contain("backtrace=")
    end
  end

  context "BaseValidationFixture" do
    it "Successfully reports errors when missing required options" do
      output = IO::Memory.new
      errors = IO::Memory.new
      command = BaseValidationFixture.new
      command.stdout = output
      command.stderr = errors

      status = command.execute([] of String)

      status.should eq(1)
      output.to_s.should contain("ERRO Missing required option")
      output.to_s.should contain("options=required-option")
      output.to_s.should contain(%(help_command="fixtures --help"))
    end

    it "Successfully reports errors when missing required args" do
      output = IO::Memory.new
      errors = IO::Memory.new
      command = BaseValidationFixture.new
      command.stdout = output
      command.stderr = errors

      status = command.execute(["--required-option"])

      status.should eq(1)
      output.to_s.should contain("ERRO Missing required argument")
      output.to_s.should contain("arguments=required")
      output.to_s.should contain(%(help_command="fixtures --help"))
    end

    it "Successfully reports errors when receiving unexpected args" do
      output = IO::Memory.new
      errors = IO::Memory.new
      command = BaseValidationFixture.new
      command.stdout = output
      command.stderr = errors

      status = command.execute(["required-arg1", "--required-option", "--value", "value", "extra"])

      status.should eq(1)
      output.to_s.should contain("ERRO Unexpected argument")
      output.to_s.should contain("arguments=extra")
      output.to_s.should contain(%(help_command="fixtures --help"))
    end

    it "Successfully reports errors when receiving unexpected options" do
      output = IO::Memory.new
      errors = IO::Memory.new
      command = BaseValidationFixture.new
      command.stdout = output
      command.stderr = errors

      status = command.execute(["required-arg1", "--required-option", "--foo"])

      status.should eq(1)
      output.to_s.should contain("ERRO Unexpected option")
      output.to_s.should contain("options=foo")
      output.to_s.should contain(%(help_command="fixtures --help"))
    end

    it "Successfully reports errors when receiving invalid options" do
      output = IO::Memory.new
      errors = IO::Memory.new
      command = BaseValidationFixture.new
      command.stdout = output
      command.stderr = errors

      status = command.execute(["required-arg1", "--required-option=invalid"])

      status.should eq(1)
      output.to_s.should contain("ERRO Invalid option")
      output.to_s.should contain("err=")
      output.to_s.should contain(%(help_command="fixtures --help"))
    end
  end
end
