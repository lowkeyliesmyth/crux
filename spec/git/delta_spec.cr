require "spec"
require "../../src/git/delta"

describe Git::Delta do
  describe ".apply" do
    it "reconstructs a target from copy and insert instructions" do
      base = "abcdefgh".to_slice
      # source size = 8, target size = 11, then:
      #   COPY  offset=0 size=5  -> "abcde"
      #   INSERT "XYZ"           -> "XYZ"
      #   COPY  offset=5 size=3  -> "fgh"
      delta = Bytes[0x08, 0x0b,
        0x90, 0x05,
        0x03, 'X'.ord, 'Y'.ord, 'Z'.ord,
        0x91, 0x05, 0x03]

      result = Git::Delta.apply(base, delta)
      String.new(result).should eq("abcdeXYZfgh")
    end

    it "treats a zero copy size as 0x10000" do
      base = Bytes.new(0x10000, 'q'.ord.to_u8)
      # source size 0x10000 (varint: 0x80 0x80 0x04), target size same,
      # then a single COPY with offset omitted and all size bytes omitted.
      delta = Bytes[0x80, 0x80, 0x04, 0x80, 0x80, 0x04, 0x80]
      result = Git::Delta.apply(base, delta)
      result.size.should eq(0x10000)
      result.all? { |byte| byte == 'q'.ord.to_u8 }.should be_true
    end

    it "raises when the base size does not match the delta header" do
      expect_raises(Git::PackError, /base size mismatch/) do
        Git::Delta.apply("abc".to_slice, Bytes[0x08, 0x01, 0x01, 'z'.ord])
      end
    end

    it "raises on a copy that runs past the base" do
      base = "abc".to_slice
      # source size 3, target size 5, COPY offset=0 size=5 (past end)
      delta = Bytes[0x03, 0x05, 0x90, 0x05]
      expect_raises(Git::PackError, /out of base bounds/) do
        Git::Delta.apply(base, delta)
      end
    end

    it "raises when output length does not match the target size" do
      base = "abcdefgh".to_slice
      # claims target size 99 but only produces 5 bytes
      delta = Bytes[0x08, 99_u8, 0x90, 0x05]
      expect_raises(Git::PackError, /expected 99/) do
        Git::Delta.apply(base, delta)
      end
    end

    it "raises on the reserved zero opcode" do
      base = "abc".to_slice
      delta = Bytes[0x03, 0x03, 0x00]
      expect_raises(Git::PackError, /reserved opcode/) do
        Git::Delta.apply(base, delta)
      end
    end
  end
end
