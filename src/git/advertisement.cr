require "./errors"
require "./pkt_line"
require "./capabilities"
require "./reference"

module Git
  # The result of the server's initial reference advertisement (git protocol
  # v0): every ref the server exposes, the capabilities it supports, and -- if
  # advertised via the `symref` capability -- the ref that `HEAD` points at.
  struct Advertisement
    # The all-zero object id, advertised by an empty repository.
    NULL_OID = "0000000000000000000000000000000000000000"

    getter references : Array(Reference)
    getter capabilities : Capabilities
    getter head_target : String?

    def initialize(@references, @capabilities, @head_target = nil)
    end

    # Reads and parses a v0 ref advertisement from `reader`, consuming up to
    # and including the terminating flush-pkt.
    def self.read(reader : PktLine::Reader) : Advertisement
      references = [] of Reference
      capabilities = Capabilities.new
      first = true

      loop do
        pkt = reader.read
        break if pkt.flush? || pkt.eof?
        next unless pkt.data?

        line = pkt.text
        if line.starts_with?("ERR ")
          raise RemoteError.new(line.lchop("ERR ").strip)
        end

        if first
          first = false
          name_and_oid, capabilities = split_capabilities(line)
          line = name_and_oid
        end

        ref = parse_ref(line)
        # An empty repository advertises a single "capabilities^{}" placeholder
        # carrying the null oid; it is not a real reference.
        references << ref unless ref.name == "capabilities^{}"
      end

      new(references, capabilities, head_target_from(capabilities))
    end

    # Looks up an advertised ref by exact name.
    def reference(name : String) : Reference?
      @references.find { |ref| ref.name == name }
    end

    # The object id `HEAD` resolves to: the symref target if advertised,
    # otherwise the oid of an explicit `HEAD` entry. Returns nil for an empty
    # repository.
    def head_oid : String?
      if target = @head_target
        if ref = reference(target)
          return ref.oid
        end
      end
      reference("HEAD").try(&.oid)
    end

    # Splits the first advertisement line at its NUL, returning the bare
    # "<oid> <name>" portion and the parsed capabilities that followed.
    private def self.split_capabilities(line : String) : {String, Capabilities}
      if nul = line.index(Char::ZERO)
        {line[0...nul], Capabilities.parse(line[(nul + 1)..])}
      else
        {line, Capabilities.new}
      end
    end

    private def self.parse_ref(line : String) : Reference
      space = line.index(' ')
      raise ProtocolError.new("malformed ref advertisement line: #{line.inspect}") unless space
      oid = line[0...space]
      name = line[(space + 1)..]
      raise ProtocolError.new("empty ref name in advertisement") if name.empty?
      Reference.new(name, oid)
    end

    # Extracts HEAD's target from a `symref=HEAD:refs/heads/...` capability.
    private def self.head_target_from(capabilities : Capabilities) : String?
      capabilities.all("symref").each do |entry|
        if colon = entry.index(':')
          source = entry[0...colon]
          return entry[(colon + 1)..] if source == "HEAD"
        end
      end
      nil
    end
  end
end
