require "../../../src/git/pkt_line"
require "../../../src/git/advertisement"

# Assembles the bytes a receive-pack server sends: a ref advertisement followed
# by a report-status response. The report does not depend on client input, so
# it can be queued up front for the in-memory FakeSession.
module FakeReceivePack
  # `report` maps ref name -> rejection reason (nil = accepted). `unpack` is the
  # unpack status line value ("ok" or an error message).
  def self.build(refs : Array({String, String}), caps : String,
                 report : Hash(String, String?) = {} of String => String?,
                 unpack : String = "ok") : Bytes
    io = IO::Memory.new
    writer = Git::PktLine::Writer.new(io)

    if refs.empty?
      writer.write("#{Git::Advertisement::NULL_OID} capabilities^{}#{Char::ZERO}#{caps}\n")
    else
      refs.each_with_index do |(oid, name), index|
        if index.zero?
          writer.write("#{oid} #{name}#{Char::ZERO}#{caps}\n")
        else
          writer.write("#{oid} #{name}\n")
        end
      end
    end
    writer.flush

    writer.write("unpack #{unpack}\n")
    report.each do |name, reason|
      writer.write(reason ? "ng #{name} #{reason}\n" : "ok #{name}\n")
    end
    writer.flush

    io.to_slice
  end
end
