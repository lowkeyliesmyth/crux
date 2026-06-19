require "./errors"
require "./pkt_line"
require "./advertisement"
require "./transport"
require "./pack_writer"

module Git
  # A single ref update sent to `receive-pack`: move `name` from `old_oid` to
  # `new_oid`. A `new_oid` of the null id requests deletion; an `old_oid` of the
  # null id requests creation.
  struct PushCommand
    getter old_oid : String
    getter new_oid : String
    getter name : String

    def initialize(@old_oid, @new_oid, @name)
    end

    def delete? : Bool
      @new_oid == Advertisement::NULL_OID
    end

    def create? : Bool
      @old_oid == Advertisement::NULL_OID
    end

    # The wire form `"<old> <new> <ref>"`.
    def to_line : String
      "#{@old_oid} #{@new_oid} #{@name}"
    end
  end

  # The server's response to a push: whether the pack unpacked, and the
  # per-ref outcome (nil reason means the ref updated successfully).
  struct PushReport
    getter unpack_status : String
    getter refs : Hash(String, String?)

    def initialize(@unpack_status = "ok", @refs = {} of String => String?)
    end

    def unpack_ok? : Bool
      @unpack_status == "ok"
    end

    # True if the pack unpacked and every ref update succeeded.
    def ok? : Bool
      unpack_ok? && @refs.values.all?(Nil)
    end

    # The refs the server rejected, mapped to their reason.
    def rejected : Hash(String, String)
      result = {} of String => String
      @refs.each { |name, reason| result[name] = reason if reason }
      result
    end
  end

  # Drives the client side of git's `receive-pack` (push) conversation over an
  # established `Session`, using protocol v0:
  #
  #   1. read the server's ref advertisement (`discover`)
  #   2. send the update commands (first carrying negotiated capabilities),
  #      terminated by a flush, then the packfile
  #   3. read the `report-status` response
  #
  # `report-status` is requested but side-band is not, so the status arrives as
  # plain pkt-lines.
  class ReceivePackClient
    AGENT = "crux-git/0"

    getter advertisement : Advertisement?

    def initialize(@session : Session)
      @reader = PktLine::Reader.new(@session.reader)
      @writer = PktLine::Writer.new(@session.writer)
    end

    # Reads and caches the server's reference advertisement.
    def discover : Advertisement
      @advertisement = Advertisement.read(@reader)
    end

    # Sends `commands` and a packfile built from `objects`, returning the
    # server's report. `discover` must have been called first.
    #
    # A pack is transmitted whenever at least one command is not a deletion
    # (even if `objects` is empty, in which case a valid zero-object pack is
    # sent); a delete-only push sends no pack.
    def send_update(commands : Array(PushCommand), objects : Indexable(Object)) : PushReport
      advertisement = @advertisement || raise(ProtocolError.new("call #discover before #send_update"))
      raise ProtocolError.new("push requires at least one command") if commands.empty?

      report_status = advertisement.capabilities.supports?("report-status")
      write_commands(commands, advertisement.capabilities, report_status)

      unless commands.all?(&.delete?)
        @session.writer.write(Pack::Writer.build(objects))
      end
      @writer.sync

      report_status ? read_report(commands) : PushReport.new
    end

    private def write_commands(commands : Array(PushCommand), server : Capabilities, report_status : Bool) : Nil
      tokens = capability_tokens(server, report_status)
      commands.each_with_index do |command, index|
        if index.zero?
          @writer.write("#{command.to_line}#{Char::ZERO}#{tokens.join(' ')}\n")
        else
          @writer.write("#{command.to_line}\n")
        end
      end
      @writer.flush
    end

    private def capability_tokens(server : Capabilities, report_status : Bool) : Array(String)
      tokens = [] of String
      tokens << "report-status" if report_status
      tokens << "agent=#{AGENT}" if server.supports?("agent")
      tokens
    end

    # Parses the `report-status` response: an `unpack` line followed by an
    # `ok <ref>` / `ng <ref> <reason>` line per command, up to a flush.
    private def read_report(commands : Array(PushCommand)) : PushReport
      first = @reader.read
      raise ProtocolError.new("expected unpack status, got end of stream") unless first.data?
      line = first.text
      unless line.starts_with?("unpack ")
        raise ProtocolError.new("malformed report-status: #{line.inspect}")
      end
      unpack_status = line.lchop("unpack ").strip

      refs = {} of String => String?
      loop do
        pkt = @reader.read
        break if pkt.flush? || pkt.eof?
        next unless pkt.data?
        parse_ref_status(pkt.text, refs)
      end

      PushReport.new(unpack_status, refs)
    end

    private def parse_ref_status(line : String, refs : Hash(String, String?)) : Nil
      if line.starts_with?("ok ")
        refs[line.lchop("ok ").strip] = nil
      elsif line.starts_with?("ng ")
        rest = line.lchop("ng ")
        if space = rest.index(' ')
          refs[rest[0...space]] = rest[(space + 1)..].strip
        else
          refs[rest.strip] = "rejected"
        end
      end
    end
  end
end
