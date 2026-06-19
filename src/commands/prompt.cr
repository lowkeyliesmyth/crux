module Crux::Commands
  # Shared interactive prompt helpers for commands that read from stdin.
  #
  # Mixed into commands so they share one consistent prompt/confirm style. The
  # methods use the command's `stdin`/`stdout`, which tests can replace with
  # in-memory IO to script a session.
  module Prompt
    # Writes a prompt label and returns the trimmed response.
    #
    # When `default` is supplied it is shown in brackets and returned if the
    # user submits an empty line. With no default, an empty line returns "".
    private def ask(label : String, default : String? = nil) : String
      if default && !default.empty?
        stdout << label.colorize.cyan << " [#{default}]: "
      else
        stdout << label.colorize.cyan << ": "
      end

      answer = (stdin.gets || "").strip
      return answer unless answer.empty?
      default || ""
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
