require "compress/zlib"
require "digest/sha1"
require "./errors"
require "./object"
require "./delta"

module Git
  # Parses a git packfile into fully-resolved objects.
  #
  # A packfile is `"PACK"`, a 4-byte version (2), a 4-byte big-endian object
  # count, the objects themselves, and a trailing 20-byte SHA-1 over all the
  # preceding bytes. Each object begins with a variable-length type/size
  # header; non-delta objects are followed by a zlib stream of their content,
  # `OFS_DELTA` objects by a back-offset to their base plus a zlib delta
  # stream, and `REF_DELTA` objects by the 20-byte id of their base plus a
  # zlib delta stream.
  module Pack
    SIGNATURE     = "PACK"
    VERSION       = 2_u32
    TRAILER_BYTES =    20

    # One object as found on the wire, before delta resolution. Non-delta
    # entries already carry their content; delta entries carry the raw delta
    # plus a reference (offset or oid) to their base.
    private class Entry
      getter offset : Int32
      getter type : ObjectType
      property base_offset : Int32?
      property base_oid : String?
      getter payload : Bytes
      property resolved : Object?

      def initialize(@offset, @type, @payload, @base_offset = nil, @base_oid = nil)
      end
    end

    class Reader
      # `base_lookup` is consulted when a `REF_DELTA` names a base object that
      # is not present in this pack -- e.g. an object already on disk when
      # applying a thin pack during fetch. For a self-contained clone pack it
      # is never needed.
      def initialize(@data : Bytes, @base_lookup : Proc(String, Object?)? = nil)
        @io = IO::Memory.new(@data, writeable: false)
        @entries = [] of Entry
        @by_offset = {} of Int32 => Entry
        @by_oid = {} of String => Object
      end

      # Parses and resolves the entire pack, returning every object keyed by
      # its id. Raises `PackError` on any structural problem and `ObjectError`
      # if a delta base cannot be located.
      def objects : Hash(String, Object)
        verify_trailer
        count = read_header
        count.times { parse_entry }
        resolve_all
        @by_oid
      end

      private def read_header : UInt32
        signature = Bytes.new(4)
        @io.read_fully?(signature) || raise(PackError.new("pack too short for header"))
        unless String.new(signature) == SIGNATURE
          raise PackError.new("bad pack signature #{String.new(signature).inspect}")
        end
        version = read_u32
        unless version == VERSION
          raise PackError.new("unsupported pack version #{version}")
        end
        read_u32
      end

      # Reads a single object header + payload, recording it for later
      # resolution and leaving `@io` positioned at the next object.
      private def parse_entry : Nil
        offset = @io.pos
        type, size = read_type_and_size

        case type
        when .ofs_delta?
          rel = read_offset_varint
          base_offset = offset - rel
          if base_offset < 0
            raise PackError.new("ofs-delta base offset #{base_offset} precedes pack start")
          end
          delta = inflate(size)
          add Entry.new(offset, type, delta, base_offset: base_offset)
        when .ref_delta?
          base = Bytes.new(20)
          @io.read_fully?(base) || raise(PackError.new("truncated ref-delta base id"))
          delta = inflate(size)
          add Entry.new(offset, type, delta, base_oid: base.hexstring)
        else
          data = inflate(size)
          add Entry.new(offset, type, data)
        end
      end

      private def add(entry : Entry) : Nil
        @entries << entry
        @by_offset[entry.offset] = entry
      end

      # Resolves every entry to a concrete `Object`, iterating to a fixpoint so
      # that delta chains of any ordering are handled: each pass resolves every
      # entry whose base is now available. If a pass makes no progress while
      # entries remain, a base is genuinely missing.
      private def resolve_all : Nil
        remaining = @entries.dup
        until remaining.empty?
          progressed = false
          remaining.reject! do |entry|
            obj = try_resolve(entry)
            next false unless obj
            entry.resolved = obj
            @by_oid[obj.oid] = obj
            progressed = true
            true
          end
          unless progressed
            missing = remaining.first
            raise ObjectError.new("cannot resolve delta base for object at pack offset #{missing.offset} (base #{missing.base_oid || missing.base_offset})")
          end
        end
      end

      # Attempts to resolve one entry, returning nil if its base is not yet
      # available.
      private def try_resolve(entry : Entry) : Object?
        case entry.type
        when .ofs_delta?
          base = @by_offset[entry.base_offset]?.try &.resolved
          return nil unless base
          Object.new(base.type, Delta.apply(base.data, entry.payload))
        when .ref_delta?
          oid = entry.base_oid || raise(PackError.new("ref-delta entry without a base id"))
          base = @by_oid[oid]? || @base_lookup.try(&.call(oid))
          return nil unless base
          Object.new(base.type, Delta.apply(base.data, entry.payload))
        else
          Object.new(entry.type, entry.payload)
        end
      end

      private def verify_trailer : Nil
        if @data.size < 12 + TRAILER_BYTES
          raise PackError.new("pack is too small to be valid")
        end
        body = @data[0, @data.size - TRAILER_BYTES]
        expected = @data[@data.size - TRAILER_BYTES, TRAILER_BYTES]
        actual = Digest::SHA1.digest(body)
        unless actual == expected
          raise PackError.new("pack checksum mismatch (expected #{expected.hexstring}, computed #{actual.hexstring})")
        end
      end

      # Reads the variable-length object header: a 3-bit type and a
      # little-endian base128 size (the low 4 size bits live in the first byte).
      private def read_type_and_size : {ObjectType, Int32}
        byte = read_byte
        type_bits = (byte >> 4) & 0x07
        size = (byte & 0x0f).to_i
        shift = 4
        while byte & 0x80 != 0
          byte = read_byte
          size |= (byte & 0x7f).to_i << shift
          shift += 7
        end
        {ObjectType.new(type_bits.to_i), size}
      end

      # Reads the offset encoding used by OFS_DELTA: a big-endian base128 value
      # with an implicit increment between continuation bytes.
      private def read_offset_varint : Int32
        byte = read_byte
        value = (byte & 0x7f).to_i
        while byte & 0x80 != 0
          value += 1
          byte = read_byte
          value = (value << 7) | (byte & 0x7f).to_i
        end
        value
      end

      # Decompresses one zlib stream of known output `size`, leaving `@io`
      # positioned immediately after the stream's adler32 trailer.
      private def inflate(size : Int32) : Bytes
        buf = Bytes.new(size)
        zlib = Compress::Zlib::Reader.new(@io)
        zlib.read_fully(buf) if size > 0
        # Draining one more byte forces the reader to consume the adler32
        # trailer, which advances @io to the start of the next object.
        unless zlib.read_byte.nil?
          raise PackError.new("zlib stream is longer than the declared object size #{size}")
        end
        buf
      rescue ex : Compress::Zlib::Error
        raise PackError.new("failed to inflate object: #{ex.message}")
      rescue IO::EOFError
        raise PackError.new("truncated zlib stream for object of size #{size}")
      end

      private def read_u32 : UInt32
        @io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
      rescue IO::EOFError
        raise PackError.new("unexpected end of pack header")
      end

      private def read_byte : UInt8
        @io.read_byte || raise(PackError.new("unexpected end of pack data"))
      end
    end
  end
end
