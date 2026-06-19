require "spec"
require "../../src/git/pkt_line"

describe Git::PktLine do
  describe Git::PktLine::Writer do
    it "frames a payload with a 4-byte hex length prefix that includes itself" do
      io = IO::Memory.new
      Git::PktLine::Writer.new(io).write("hello")
      # "hello" is 5 bytes, + 4 prefix bytes = 9 = 0x0009
      io.to_s.should eq("0009hello")
    end

    it "writes a flush packet as 0000" do
      io = IO::Memory.new
      Git::PktLine::Writer.new(io).flush
      io.to_s.should eq("0000")
    end

    it "rejects payloads larger than the maximum" do
      io = IO::Memory.new
      writer = Git::PktLine::Writer.new(io)
      expect_raises(Git::ProtocolError) do
        writer.write(Bytes.new(Git::PktLine::MAX_PAYLOAD + 1))
      end
    end
  end

  describe Git::PktLine::Reader do
    it "decodes a data packet" do
      reader = Git::PktLine::Reader.new(IO::Memory.new("0009hello"))
      pkt = reader.read
      pkt.data?.should be_true
      String.new(pkt.payload).should eq("hello")
    end

    it "decodes flush, delim and response-end magic packets" do
      reader = Git::PktLine::Reader.new(IO::Memory.new("000000010002"))
      reader.read.kind.should eq(Git::PktLine::Kind::Flush)
      reader.read.kind.should eq(Git::PktLine::Kind::Delim)
      reader.read.kind.should eq(Git::PktLine::Kind::ResponseEnd)
    end

    it "returns Eof when the stream ends on a boundary" do
      reader = Git::PktLine::Reader.new(IO::Memory.new(""))
      reader.read.eof?.should be_true
    end

    it "strips a single trailing newline in #text" do
      reader = Git::PktLine::Reader.new(IO::Memory.new("000ahello\n"))
      reader.read.text.should eq("hello")
    end

    it "raises on a non-hex length prefix" do
      reader = Git::PktLine::Reader.new(IO::Memory.new("zzzz"))
      expect_raises(Git::ProtocolError) { reader.read }
    end

    it "raises on a truncated payload" do
      reader = Git::PktLine::Reader.new(IO::Memory.new("0009hel"))
      expect_raises(Git::ProtocolError) { reader.read }
    end

    it "round-trips an arbitrary payload through writer and reader" do
      io = IO::Memory.new
      writer = Git::PktLine::Writer.new(io)
      writer.write("want 1234\n")
      writer.flush
      writer.write("done\n")

      reader = Git::PktLine::Reader.new(IO::Memory.new(io.to_s))
      reader.read.text.should eq("want 1234")
      reader.read.flush?.should be_true
      reader.read.text.should eq("done")
    end

    it "iterates data packets up to a flush with each_until_flush" do
      io = IO::Memory.new
      writer = Git::PktLine::Writer.new(io)
      writer.write("a\n")
      writer.write("b\n")
      writer.flush

      collected = [] of String
      Git::PktLine::Reader.new(IO::Memory.new(io.to_s)).each_until_flush do |pkt|
        collected << pkt.text
      end
      collected.should eq(["a", "b"])
    end
  end
end
