require "./errors"
require "./url"

module Git
  # A live, full-duplex connection to a remote git service. `reader` carries
  # bytes from the remote's stdout; `writer` carries bytes to its stdin.
  # Callers must invoke `finish` once the exchange is complete.
  abstract class Session
    abstract def reader : IO
    abstract def writer : IO

    # Signals that the client is done sending; closes the write side so the
    # remote sees EOF, then waits for it to exit. Raises `TransportError` if
    # the remote process failed.
    abstract def finish : Nil

    # Closes both sides without waiting; used to abort on error.
    abstract def abort : Nil
  end

  # Establishes `Session`s to a remote. Abstracted so the protocol code can be
  # driven by an in-memory fake in tests, independent of any real subprocess.
  abstract class Transport
    # The git service to run remotely for read operations.
    UPLOAD_PACK = "git-upload-pack"
    # The git service to run remotely for write operations (push, future).
    RECEIVE_PACK = "git-receive-pack"

    abstract def connect(service : String) : Session

    # Convenience for the fetch/clone read path.
    def upload_pack : Session
      connect(UPLOAD_PACK)
    end
  end

  # A `Session` backed by a spawned subprocess (the system `ssh` client).
  class ProcessSession < Session
    def initialize(@process : Process)
    end

    def reader : IO
      @process.output
    end

    def writer : IO
      @process.input
    end

    def finish : Nil
      @process.input.close
      status = @process.wait
      unless status.success?
        raise TransportError.new("remote process exited with status #{status.exit_code}")
      end
    end

    def abort : Nil
      @process.input.close rescue nil
      @process.output.close rescue nil
      @process.terminate rescue nil
      @process.wait rescue nil
    end
  end

  # Transport that runs the remote git service by invoking the system `ssh`
  # client -- exactly how git's own `ssh://` remotes work. No SSH protocol is
  # implemented here; authentication, host-key checking and encryption are all
  # delegated to the user's configured ssh client.
  class SSHTransport < Transport
    # @ssh_command is the ssh executable (overridable for e.g. `plink`).
    # @options are extra arguments inserted before the destination, letting
    # callers pass identity files, config, etc.
    def initialize(@url : URL, @ssh_command : String = "ssh", @options : Array(String) = [] of String)
    end

    def connect(service : String) : Session
      args = build_args(service)
      begin
        process = Process.new(
          @ssh_command,
          args,
          input: Process::Redirect::Pipe,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Inherit,
        )
      rescue ex : IO::Error | RuntimeError
        raise TransportError.new("failed to start #{@ssh_command}: #{ex.message}")
      end
      ProcessSession.new(process)
    end

    # Builds the ssh argument vector: connection options, then the destination,
    # then a single remote command string `git-upload-pack '<path>'`.
    private def build_args(service : String) : Array(String)
      args = ["-o", "BatchMode=yes"]
      if port = @url.port
        args << "-p" << port.to_s
      end
      args.concat(@options)
      args << @url.ssh_destination
      args << "#{service} #{single_quote(@url.path)}"
      args
    end

    # Single-quotes a path for the remote POSIX shell, escaping embedded single
    # quotes via the standard `'\''` trick.
    private def single_quote(value : String) : String
      "'" + value.gsub("'", "'\\''") + "'"
    end
  end
end
