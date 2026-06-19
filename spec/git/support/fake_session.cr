require "../../../src/git/transport"
require "../../../src/git/pkt_line"

# An in-memory `Git::Session` for driving the protocol code without a real
# subprocess. The bytes the "server" should send are supplied up front;
# everything the client writes is captured in `sent` for assertions.
class FakeSession < Git::Session
  getter sent : IO::Memory
  getter? finished = false
  getter? aborted = false

  def initialize(server_bytes : Bytes)
    @reader_io = IO::Memory.new(server_bytes)
    @sent = IO::Memory.new
  end

  def reader : IO
    @reader_io
  end

  def writer : IO
    @sent
  end

  def finish : Nil
    @finished = true
  end

  def abort : Nil
    @aborted = true
  end
end

# A `Git::Transport` that always hands back the same prepared `FakeSession`.
class FakeTransport < Git::Transport
  getter session : FakeSession

  def initialize(server_bytes : Bytes)
    @session = FakeSession.new(server_bytes)
  end

  def connect(service : String) : Git::Session
    @session
  end
end

# Assembles the bytes an upload-pack server sends for a single-round clone:
# a ref advertisement, a NAK, and the packfile multiplexed onto side-band
# channel 1.
module FakeUploadPack
  def self.build(refs : Array({String, String}), caps : String, pack : Bytes, chunk_size : Int32 = 64) : Bytes
    io = IO::Memory.new
    writer = Git::PktLine::Writer.new(io)

    refs.each_with_index do |(oid, name), index|
      if index.zero?
        writer.write("#{oid} #{name}#{Char::ZERO}#{caps}\n")
      else
        writer.write("#{oid} #{name}\n")
      end
    end
    writer.flush

    writer.write("NAK\n")

    offset = 0
    while offset < pack.size
      slice = pack[offset, Math.min(chunk_size, pack.size - offset)]
      framed = Bytes.new(slice.size + 1)
      framed[0] = 1_u8 # channel 1: pack data
      slice.copy_to(framed + 1)
      writer.write(framed)
      offset += slice.size
    end
    writer.flush

    io.to_slice
  end
end
