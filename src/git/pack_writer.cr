require "compress/zlib"
require "digest/sha1"
require "./errors"
require "./object"
require "./pack"

module Git
  module Pack
    # Serializes objects into a git v2 packfile, the inverse of `Pack::Reader`.
    #
    # Every object is written in its full (non-delta) form: a variable-length
    # type/size header followed by a zlib stream of the content. Delta
    # compression is deliberately not produced -- a non-delta, non-thin pack is
    # always valid input to `git index-pack`, so this keeps the push path simple
    # and correct at the cost of a larger transfer.
    class Writer
      # Builds a complete packfile (including the trailing SHA-1 checksum) for
      # the given objects.
      def self.build(objects : Indexable(Object)) : Bytes
        body = IO::Memory.new
        body << SIGNATURE
        body.write_bytes(VERSION, IO::ByteFormat::BigEndian)
        body.write_bytes(objects.size.to_u32, IO::ByteFormat::BigEndian)

        objects.each { |object| write_object(body, object) }

        digest = Digest::SHA1.digest(body.to_slice)
        result = IO::Memory.new(body.size + TRAILER_BYTES)
        result.write(body.to_slice)
        result.write(digest)
        result.to_slice
      end

      private def self.write_object(io : IO, object : Object) : Nil
        write_type_and_size(io, object.type, object.data.size)
        Compress::Zlib::Writer.open(io, &.write(object.data))
      end

      # Writes the variable-length object header: a 3-bit type in the first
      # byte's high bits and the size as a little-endian base128 value (low 4
      # bits in the first byte).
      private def self.write_type_and_size(io : IO, type : ObjectType, size : Int32) : Nil
        byte = ((type.value << 4) | (size & 0x0f)).to_u8
        size >>= 4
        while size > 0
          io.write_byte(byte | 0x80_u8)
          byte = (size & 0x7f).to_u8
          size >>= 7
        end
        io.write_byte(byte)
      end
    end
  end
end
