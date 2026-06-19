require "./errors"

module Git
  # A parsed git-over-SSH remote location.
  #
  # Two URL syntaxes are recognised, matching git itself:
  #
  #   * The explicit form `ssh://[user@]host[:port]/path`
  #   * The scp-like short form `[user@]host:path`
  #
  # In the scp-like form a port cannot be specified and the path is taken
  # literally (git treats it as relative to the login directory unless it
  # begins with `/` or `~`). The explicit `ssh://` form always uses an
  # absolute-looking path beginning with `/`.
  struct URL
    getter user : String?
    getter host : String
    getter port : Int32?
    getter path : String

    def initialize(@host : String, @path : String, @user : String? = nil, @port : Int32? = nil)
    end

    # Parses a remote URL string in either supported syntax.
    # Raises `InvalidURLError` if the string is not a recognisable SSH remote.
    def self.parse(raw : String) : URL
      raw = raw.strip
      raise InvalidURLError.new("empty remote URL") if raw.empty?

      if raw.starts_with?("ssh://") || raw.starts_with?("git+ssh://")
        parse_scheme(raw)
      else
        parse_scp_like(raw)
      end
    end

    # Parses the explicit `ssh://` (or `git+ssh://`) form.
    private def self.parse_scheme(raw : String) : URL
      without_scheme = raw.sub(/\Agit\+ssh:\/\//, "").sub(/\Assh:\/\//, "")

      slash = without_scheme.index('/')
      raise InvalidURLError.new("ssh URL is missing a path: #{raw.inspect}") unless slash
      authority = without_scheme[0...slash]
      path = without_scheme[slash..]
      raise InvalidURLError.new("ssh URL has empty authority: #{raw.inspect}") if authority.empty?

      user, hostport = split_user(authority)
      host, port = split_host_port(hostport, raw)
      raise InvalidURLError.new("ssh URL has empty host: #{raw.inspect}") if host.empty?

      new(host: host, path: path, user: user, port: port)
    end

    # Parses the scp-like `[user@]host:path` short form. The first colon that
    # is not part of a leading `user@` segment separates host from path.
    private def self.parse_scp_like(raw : String) : URL
      user, rest = split_user(raw)

      colon = rest.index(':')
      unless colon
        raise InvalidURLError.new("not an SSH remote (missing ':' or 'ssh://'): #{raw.inspect}")
      end
      # A '/' before the ':' means this is a local path, not an scp remote
      # (e.g. "./dir:name"). git applies the same heuristic.
      if (slash = rest.index('/')) && slash < colon
        raise InvalidURLError.new("not an SSH remote (looks like a local path): #{raw.inspect}")
      end

      host = rest[0...colon]
      path = rest[(colon + 1)..]
      raise InvalidURLError.new("scp-like remote has empty host: #{raw.inspect}") if host.empty?
      raise InvalidURLError.new("scp-like remote has empty path: #{raw.inspect}") if path.empty?

      new(host: host, path: path, user: user, port: nil)
    end

    # Splits an optional leading "user@" off the front of a string.
    private def self.split_user(value : String) : {String?, String}
      if at = value.index('@')
        {value[0...at], value[(at + 1)..]}
      else
        {nil, value}
      end
    end

    # Splits "host" or "host:port" (IPv6 literals in brackets are supported).
    private def self.split_host_port(value : String, raw : String) : {String, Int32?}
      if value.starts_with?('[')
        close = value.index(']')
        raise InvalidURLError.new("malformed IPv6 host in #{raw.inspect}") unless close
        host = value[1...close]
        remainder = value[(close + 1)..]
        return {host, nil} if remainder.empty?
        unless remainder.starts_with?(':')
          raise InvalidURLError.new("malformed authority in #{raw.inspect}")
        end
        {host, parse_port(remainder[1..], raw)}
      elsif colon = value.index(':')
        {value[0...colon], parse_port(value[(colon + 1)..], raw)}
      else
        {value, nil}
      end
    end

    private def self.parse_port(value : String, raw : String) : Int32
      port = value.to_i?
      unless port && port > 0 && port <= 65_535
        raise InvalidURLError.new("invalid port #{value.inspect} in #{raw.inspect}")
      end
      port
    end

    # The `[user@]host` token to pass to the ssh client.
    def ssh_destination : String
      user ? "#{user}@#{host}" : host
    end

    def to_s(io : IO) : Nil
      io << "ssh://"
      io << user << '@' if user
      io << host
      io << ':' << port if port
      io << path
    end
  end
end
