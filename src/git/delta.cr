require "./errors"

module Git
  # Implements git's binary delta format, used by the `OFS_DELTA` and
  # `REF_DELTA` packfile object encodings. A delta is applied against a base
  # object to reconstruct a target object.
  #
  # The encoding is: a little-endian base128 source size, a little-endian
  # base128 target size, then a sequence of instructions. Each instruction is
  # either a COPY (high bit of the opcode set -- copy a run of bytes from the
  # base at a given offset) or an INSERT (high bit clear -- the opcode is a
  # length and that many literal bytes follow in the delta stream).
  module Delta
    # Reconstructs the target object by applying `delta` to `base`.
    # Raises `PackError` if the delta is malformed or the declared sizes do
    # not match what the instructions actually produce.
    def self.apply(base : Bytes, delta : Bytes) : Bytes
      pos = 0

      source_size, pos = read_varint(delta, pos)
      unless source_size == base.size
        raise PackError.new("delta base size mismatch: header says #{source_size}, base is #{base.size}")
      end

      target_size, pos = read_varint(delta, pos)

      result = Bytes.new(target_size)
      written = 0

      while pos < delta.size
        opcode = delta[pos]
        pos += 1

        if opcode & 0x80 != 0
          written, pos = apply_copy(opcode, base, delta, pos, result, written)
        elsif opcode != 0
          written, pos = apply_insert(opcode, delta, pos, result, written)
        else
          raise PackError.new("delta contains reserved opcode 0x00")
        end
      end

      unless written == target_size
        raise PackError.new("delta produced #{written} bytes, expected #{target_size}")
      end
      result
    end

    # Decodes a COPY instruction. The opcode's low 7 bits select which of the
    # four offset bytes and three size bytes are present (little-endian); a
    # zero size is interpreted as 0x10000.
    private def self.apply_copy(opcode : UInt8, base : Bytes, delta : Bytes, pos : Int32, result : Bytes, written : Int32) : {Int32, Int32}
      offset = 0
      4.times do |i|
        if opcode & (0x01 << i) != 0
          offset |= read_byte(delta, pos).to_i << (8 * i)
          pos += 1
        end
      end

      size = 0
      3.times do |i|
        if opcode & (0x10 << i) != 0
          size |= read_byte(delta, pos).to_i << (8 * i)
          pos += 1
        end
      end
      size = 0x10000 if size == 0

      if offset + size > base.size
        raise PackError.new("delta copy out of base bounds (offset #{offset}, size #{size}, base #{base.size})")
      end
      if written + size > result.size
        raise PackError.new("delta copy overflows target buffer")
      end

      base[offset, size].copy_to(result + written)
      {written + size, pos}
    end

    # Decodes an INSERT instruction: copy `opcode` literal bytes straight from
    # the delta stream into the output.
    private def self.apply_insert(opcode : UInt8, delta : Bytes, pos : Int32, result : Bytes, written : Int32) : {Int32, Int32}
      size = opcode.to_i
      if pos + size > delta.size
        raise PackError.new("delta insert reads past end of stream")
      end
      if written + size > result.size
        raise PackError.new("delta insert overflows target buffer")
      end
      delta[pos, size].copy_to(result + written)
      {written + size, pos + size}
    end

    # Reads a little-endian base128 varint as used for the delta source and
    # target sizes (low 7 bits first, high bit signals continuation).
    private def self.read_varint(delta : Bytes, pos : Int32) : {Int32, Int32}
      value = 0
      shift = 0
      loop do
        byte = read_byte(delta, pos)
        pos += 1
        value |= (byte & 0x7f).to_i << shift
        break if byte & 0x80 == 0
        shift += 7
      end
      {value, pos}
    end

    private def self.read_byte(delta : Bytes, pos : Int32) : UInt8
      if pos >= delta.size
        raise PackError.new("unexpected end of delta stream")
      end
      delta[pos]
    end
  end
end
