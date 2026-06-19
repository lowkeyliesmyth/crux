module Git
  # Base class for every error raised by the git module. Catching this is
  # sufficient to handle any failure originating from clone/fetch/pull.
  class Error < Exception
  end

  # Raised when a URL cannot be understood as an SSH git remote.
  class InvalidURLError < Error
  end

  # Raised when the remote transport (the `ssh` subprocess) cannot be started
  # or exits abnormally.
  class TransportError < Error
  end

  # Raised when bytes received from the remote do not conform to the git
  # pkt-line / pack protocol.
  class ProtocolError < Error
  end

  # Raised when the remote reports an error (e.g. side-band channel 3, or a
  # `ERR` pkt-line during ref advertisement).
  class RemoteError < Error
  end

  # Raised when a packfile is malformed or an object inside it cannot be
  # decoded (bad header, truncated zlib stream, unresolvable delta, ...).
  class PackError < Error
  end

  # Raised when an object's computed SHA-1 does not match the id it was
  # expected to have, or a referenced object is missing.
  class ObjectError < Error
  end
end
