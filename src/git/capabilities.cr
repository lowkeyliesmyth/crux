module Git
  # The set of protocol capabilities a server advertises (or a client
  # requests). Capabilities are space-separated tokens that are either bare
  # flags (`ofs-delta`, `side-band-64k`) or `key=value` pairs (`agent=...`,
  # `symref=HEAD:refs/heads/main`). A key may legitimately repeat, so values
  # are kept as lists.
  struct Capabilities
    getter flags : Set(String)
    getter values : Hash(String, Array(String))

    def initialize(@flags = Set(String).new, @values = Hash(String, Array(String)).new)
    end

    # Parses a capability string (the bytes following the first NUL on the
    # ref-advertisement's first line).
    def self.parse(text : String) : Capabilities
      caps = new
      text.split(' ', remove_empty: true).each do |token|
        if eq = token.index('=')
          key = token[0...eq]
          value = token[(eq + 1)..]
          (caps.values[key] ||= [] of String) << value
        else
          caps.flags << token
        end
      end
      caps
    end

    # True if the bare flag (or a `key=...` capability) is present.
    def supports?(name : String) : Bool
      @flags.includes?(name) || @values.has_key?(name)
    end

    # The first value for a `key=value` capability, if any.
    def value(key : String) : String?
      @values[key]?.try(&.first?)
    end

    # All values for a `key=value` capability (e.g. multiple `symref` entries).
    def all(key : String) : Array(String)
      @values[key]? || [] of String
    end
  end
end
