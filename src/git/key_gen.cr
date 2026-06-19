module Crux::Git
  # Abstract collaborator for SSH key generation.
  #
  # Isolated behind an interface (like Runner) so the only real shell-out to
  # ssh-keygen lives in one place and `profile add` can be tested with a fake
  # that fabricates key files instead of invoking ssh-keygen.
  abstract class KeyGen
    # Returns true if ssh-keygen is available on PATH.
    abstract def available? : Bool

    # Generates an ed25519 keypair at `path` (private) and `path`.pub (public),
    # with `comment` embedded in the public key. Returns the invocation Result.
    abstract def generate(path : String, comment : String) : Result
  end

  # Concrete KeyGen that shells out to the system ssh-keygen binary.
  class RealKeyGen < KeyGen
    def available? : Bool
      !!Process.find_executable("ssh-keygen")
    end

    def generate(path : String, comment : String) : Result
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new

      # -N "" => no passphrase; ed25519 is the modern default for signing/auth.
      status = Process.run(
        "ssh-keygen",
        ["-t", "ed25519", "-f", path, "-N", "", "-C", comment],
        output: stdout_io,
        error: stderr_io,
      )

      Result.new(status.exit_code, stdout_io.to_s, stderr_io.to_s)
    end
  end
end
