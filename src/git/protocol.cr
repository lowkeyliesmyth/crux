require "./errors"
require "./pkt_line"
require "./advertisement"
require "./transport"

module Git
  # Drives the client side of git's `upload-pack` (fetch) conversation over an
  # established `Session`, using protocol v0:
  #
  #   1. read the server's ref advertisement (`discover`)
  #   2. send `want` lines (plus negotiated capabilities) and any `have` lines,
  #      terminated by `done`
  #   3. read the acknowledgement and the packfile, de-multiplexing the
  #      side-band channels if that capability was negotiated
  #
  # The class is transport-agnostic: it only needs the `reader`/`writer` IOs
  # the `Session` exposes, so it is exercised in tests with an in-memory fake.
  class UploadPackClient
    AGENT = "crux-git/0"

    # The capabilities actually negotiated for a fetch: the tokens to send on
    # the first `want` line, and whether the pack will arrive side-band-muxed.
    private struct Negotiated
      getter tokens : Array(String)
      getter? side_band : Bool

      def initialize(@tokens, @side_band)
      end
    end

    getter advertisement : Advertisement?

    # Optional sink for human-readable remote progress (side-band channel 2).
    property progress : IO?

    def initialize(@session : Session)
      @reader = PktLine::Reader.new(@session.reader)
      @writer = PktLine::Writer.new(@session.writer)
    end

    # Reads and caches the server's reference advertisement.
    def discover : Advertisement
      @advertisement = Advertisement.read(@reader)
    end

    # Negotiates capabilities, requests `wants` (excluding `haves`), and returns
    # the raw packfile bytes. `discover` must have been called first.
    def fetch(wants : Enumerable(String), haves : Enumerable(String) = [] of String) : Bytes
      adv = @advertisement || raise(ProtocolError.new("call #discover before #fetch"))
      want_list = wants.to_a.uniq
      raise ProtocolError.new("fetch requires at least one want") if want_list.empty?

      negotiated = select_capabilities(adv.capabilities)
      send_request(want_list, haves.to_a, negotiated)
      read_acknowledgement
      read_pack(negotiated)
    end

    # Chooses the subset of advertised capabilities we want for a fetch.
    private def select_capabilities(server : Capabilities) : Negotiated
      tokens = [] of String
      side_band = false

      if server.supports?("side-band-64k")
        tokens << "side-band-64k"
        side_band = true
      elsif server.supports?("side-band")
        tokens << "side-band"
        side_band = true
      end

      tokens << "ofs-delta" if server.supports?("ofs-delta")
      tokens << "no-progress" if server.supports?("no-progress") && @progress.nil?
      tokens << "agent=#{AGENT}" if server.supports?("agent")

      Negotiated.new(tokens, side_band)
    end

    private def send_request(wants : Array(String), haves : Array(String), negotiated : Negotiated) : Nil
      wants.each_with_index do |oid, index|
        if index.zero?
          @writer.write("want #{oid} #{negotiated.tokens.join(' ')}\n")
        else
          @writer.write("want #{oid}\n")
        end
      end
      @writer.flush
      haves.each { |oid| @writer.write("have #{oid}\n") }
      @writer.write("done\n")
      @writer.sync
    end

    # Consumes the single NAK/ACK line that precedes the pack. (Multi-ack is not
    # requested, so exactly one acknowledgement line is expected.)
    private def read_acknowledgement : Nil
      pkt = @reader.read
      raise ProtocolError.new("expected NAK/ACK, got end of stream") unless pkt.data?
      line = pkt.text
      unless line == "NAK" || line.starts_with?("ACK")
        raise ProtocolError.new("unexpected acknowledgement: #{line.inspect}")
      end
    end

    private def read_pack(negotiated : Negotiated) : Bytes
      negotiated.side_band? ? read_sideband_pack : read_raw_pack
    end

    # De-multiplexes side-band pkt-lines: channel 1 is pack data, channel 2 is
    # progress, channel 3 is a fatal remote error.
    private def read_sideband_pack : Bytes
      buffer = IO::Memory.new
      loop do
        pkt = @reader.read
        break if pkt.flush? || pkt.eof?
        next unless pkt.data?

        payload = pkt.payload
        raise ProtocolError.new("empty side-band packet") if payload.empty?
        channel = payload[0]
        rest = payload + 1

        case channel
        when 1 then buffer.write(rest)
        when 2 then @progress.try(&.write(rest))
        when 3 then raise RemoteError.new(String.new(rest).strip)
        else
          raise ProtocolError.new("unknown side-band channel #{channel}")
        end
      end
      buffer.to_slice
    end

    # Without side-band, the packfile is simply the remaining raw bytes on the
    # connection after the acknowledgement.
    private def read_raw_pack : Bytes
      buffer = IO::Memory.new
      IO.copy(@session.reader, buffer)
      buffer.to_slice
    end
  end
end
