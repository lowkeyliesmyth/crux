require "compress/zlib"
require "digest/sha1"
require "../../../src/git/object"

# Test-only helper that assembles valid v2 packfiles. It mirrors the wire
# format the production `Git::Pack::Reader` consumes, so the reader is
# exercised against real bytes rather than mocks. (The production module is
# read-only for now; pack *writing* will live in the push path later.)
class PackBuilder
  private record Item, type : Git::ObjectType, payload : Bytes,
    base_oid : String? = nil, base_index : Int32? = nil

  def initialize
    @items = [] of Item
  end

  # Adds a literal (non-delta) object, returning its git object id.
  def add(type : Git::ObjectType, content : String | Bytes) : String
    bytes = content.is_a?(String) ? content.to_slice : content
    @items << Item.new(type, bytes)
    Git::Object.new(type, bytes).oid
  end

  # Adds a REF_DELTA object referencing a base by object id.
  def add_ref_delta(base_oid : String, delta : Bytes) : Nil
    @items << Item.new(Git::ObjectType::RefDelta, delta, base_oid: base_oid)
  end

  # Adds an OFS_DELTA object referencing an earlier item by its index.
  def add_ofs_delta(base_index : Int32, delta : Bytes) : Nil
    @items << Item.new(Git::ObjectType::OfsDelta, delta, base_index: base_index)
  end

  # Serializes the pack, appending the trailing SHA-1 checksum.
  def build : Bytes
    body = IO::Memory.new
    body << "PACK"
    body.write_bytes(2_u32, IO::ByteFormat::BigEndian)
    body.write_bytes(@items.size.to_u32, IO::ByteFormat::BigEndian)

    offsets = [] of Int32
    @items.each_with_index do |item, index|
      offsets << body.size
      write_object(body, item, offsets, index)
    end

    digest = Digest::SHA1.digest(body.to_slice)
    result = IO::Memory.new
    result.write(body.to_slice)
    result.write(digest)
    result.to_slice
  end

  private def write_object(io : IO::Memory, item : Item, offsets : Array(Int32), index : Int32) : Nil
    write_type_and_size(io, item.type, item.payload.size)

    case item.type
    when .ofs_delta?
      if base_index = item.base_index
        write_offset(io, offsets[index] - offsets[base_index])
      end
    when .ref_delta?
      if base_oid = item.base_oid
        io.write(base_oid.hexbytes)
      end
    end

    Compress::Zlib::Writer.open(io, &.write(item.payload))
  end

  private def write_type_and_size(io : IO, type : Git::ObjectType, size : Int32) : Nil
    byte = ((type.value << 4) | (size & 0x0f)).to_u8
    size >>= 4
    while size > 0
      io.write_byte(byte | 0x80_u8)
      byte = (size & 0x7f).to_u8
      size >>= 7
    end
    io.write_byte(byte)
  end

  private def write_offset(io : IO, offset : Int32) : Nil
    bytes = [(offset & 0x7f).to_u8]
    offset >>= 7
    while offset != 0
      offset -= 1
      bytes.unshift((0x80 | (offset & 0x7f)).to_u8)
      offset >>= 7
    end
    bytes.each { |byte| io.write_byte(byte) }
  end
end
