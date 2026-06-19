require "./errors"

module Git
  # The pkt-line is git's fundamental framing unit for the smart transfer
  # protocol. Each packet is a 4-byte ASCII-hex length prefix (the length
  # *includes* the 4 prefix bytes) followed by that many bytes of payload.
  #
  # Three length values are special "magic" packets that carry no payload:
  #
  #   * `0000` - flush-pkt   : marks the end of a section
  #   * `0001` - delim-pkt   : separates sections (protocol v2)
  #   * `0002` - response-end: ends a stateless response (protocol v2)
  #
  # See gitprotocol-common(5) for the authoritative description.
  module PktLine
    # The largest payload a single pkt-line may carry. The 4-byte length is
    # hex so the maximum encodable length is 0xFFFF, but git caps the usable
    # data at 65516 bytes (0xFFF0 total - 4 header bytes).
    MAX_PAYLOAD = 65516

    FLUSH_BYTES = "0000".to_slice

    # The kind of a decoded packet. `Data` carries a payload; the others are
    # the magic zero-length control packets, and `Eof` signals the stream
    # closed cleanly at a packet boundary.
    enum Kind
      Data
      Flush
      Delim
      ResponseEnd
      Eof
    end

    # A single decoded packet. For `Kind::Data` the `payload` holds the bytes
    # after the length prefix (with no trailing-newline stripping); for every
    # other kind it is empty.
    struct Packet
      getter kind : Kind
      getter payload : Bytes

      def initialize(@kind : Kind, @payload : Bytes = Bytes.empty)
      end

      def data? : Bool
        @kind.data?
      end

      def flush? : Bool
        @kind.flush?
      end

      def eof? : Bool
        @kind.eof?
      end

      # The payload decoded as UTF-8 text with any single trailing newline
      # removed -- convenient for the line-oriented control messages
      # (`want`, `have`, ref advertisement lines, ...).
      def text : String
        str = String.new(@payload)
        str.ends_with?('\n') ? str[0...-1] : str
      end
    end

    # Reads pkt-lines from an underlying IO.
    class Reader
      def initialize(@io : IO)
      end

      # Reads and decodes the next packet. Raises `ProtocolError` on a
      # malformed length prefix or a truncated payload. Returns a packet of
      # `Kind::Eof` if the stream ends exactly on a packet boundary.
      def read : Packet
        header = Bytes.new(4)
        read_count = @io.read(header)
        return Packet.new(Kind::Eof) if read_count == 0
        if read_count < 4
          raise ProtocolError.new("truncated pkt-line length prefix")
        end

        length = parse_length(header)
        case length
        when 0 then return Packet.new(Kind::Flush)
        when 1 then return Packet.new(Kind::Delim)
        when 2 then return Packet.new(Kind::ResponseEnd)
        end

        if length < 4
          raise ProtocolError.new("invalid pkt-line length #{length}")
        end

        payload = Bytes.new(length - 4)
        unless @io.read_fully?(payload)
          raise ProtocolError.new("truncated pkt-line payload (wanted #{payload.size} bytes)")
        end
        Packet.new(Kind::Data, payload)
      end

      # Yields each `Kind::Data` packet until a flush-pkt or EOF is reached.
      # The terminating flush/eof packet is consumed but not yielded.
      def each_until_flush(& : Packet ->) : Nil
        loop do
          pkt = read
          break if pkt.flush? || pkt.eof?
          yield pkt
        end
      end

      private def parse_length(header : Bytes) : Int32
        header.each do |byte|
          unless hex_digit?(byte)
            raise ProtocolError.new("non-hex byte in pkt-line length prefix")
          end
        end
        String.new(header).to_i(16)
      end

      private def hex_digit?(byte : UInt8) : Bool
        (byte >= '0'.ord && byte <= '9'.ord) ||
          (byte >= 'a'.ord && byte <= 'f'.ord) ||
          (byte >= 'A'.ord && byte <= 'F'.ord)
      end
    end

    # Writes pkt-lines to an underlying IO.
    class Writer
      def initialize(@io : IO)
      end

      # Encodes `payload` as a single data pkt-line. The payload must not
      # exceed `MAX_PAYLOAD`; callers that may exceed it should chunk first.
      def write(payload : Bytes) : Nil
        if payload.size > MAX_PAYLOAD
          raise ProtocolError.new("pkt-line payload of #{payload.size} bytes exceeds maximum")
        end
        total = payload.size + 4
        @io.print(format_length(total))
        @io.write(payload)
      end

      # Convenience overload for textual commands. Note that git's line
      # commands generally include their own trailing newline -- this method
      # does not add one.
      def write(payload : String) : Nil
        write(payload.to_slice)
      end

      # Writes a flush-pkt (`0000`).
      def flush : Nil
        @io.write(FLUSH_BYTES)
      end

      # Forces the underlying IO to flush its buffer to the peer.
      def sync : Nil
        @io.flush
      end

      private def format_length(value : Int32) : String
        value.to_s(16).rjust(4, '0')
      end
    end
  end
end
