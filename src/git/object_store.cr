require "compress/zlib"
require "./errors"
require "./object"

module Git
  # Reads and writes loose objects under a git object directory
  # (`<git-dir>/objects`). An object with id `abcd...` is stored zlib-compressed
  # at `ab/cd...`, where the compressed payload is the loose form
  # `"<type> <size>\0<content>"`.
  #
  # Packed objects are not read here -- the fetch path resolves a pack fully in
  # memory and explodes it into loose objects via `write`, so a freshly cloned
  # repository contains only loose objects. (A pack/idx reader can be added
  # later without changing this interface.)
  class ObjectStore
    def initialize(@objects_dir : String)
    end

    # True if a loose object with this id already exists on disk.
    def contains?(oid : String) : Bool
      File.exists?(path_for(oid))
    end

    # Writes `object` as a loose object if not already present, returning its
    # id. Writing is atomic (temp file + rename) so a concurrent reader never
    # sees a partial object.
    def write(object : Object) : String
      oid = object.oid
      path = path_for(oid)
      return oid if File.exists?(path)

      Dir.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp-#{Process.pid}-#{Random.rand(UInt32)}"
      begin
        File.open(tmp, "wb") do |file|
          Compress::Zlib::Writer.open(file, &.write(object.to_loose))
        end
        File.rename(tmp, path)
      rescue ex
        File.delete(tmp) if File.exists?(tmp)
        raise ex
      end
      oid
    end

    # Writes every object in the map, returning the count written.
    def write_all(objects : Enumerable(Object)) : Int32
      objects.reduce(0) do |count, object|
        write(object)
        count + 1
      end
    end

    # Reads and decodes a loose object, or nil if it is not stored.
    def read(oid : String) : Object?
      path = path_for(oid)
      return nil unless File.exists?(path)

      raw = File.open(path, "rb") do |file|
        decompressed = IO::Memory.new
        Compress::Zlib::Reader.open(file) { |zlib| IO.copy(zlib, decompressed) }
        decompressed.to_slice
      end
      decode(oid, raw)
    end

    # A proc suitable for `Pack::Reader`'s external base lookup, so a thin pack
    # received during fetch can resolve deltas against objects already on disk.
    def base_lookup : Proc(String, Object?)
      ->(oid : String) { read(oid) }
    end

    # Parses the loose form `"<type> <size>\0<content>"` and validates the
    # declared size and resulting id.
    private def decode(oid : String, raw : Bytes) : Object
      nul = raw.index(0_u8)
      raise ObjectError.new("loose object #{oid} has no header terminator") unless nul

      header = String.new(raw[0, nul])
      space = header.index(' ')
      raise ObjectError.new("loose object #{oid} has a malformed header") unless space

      type = ObjectType.from_loose_name(header[0...space])
      declared = header[(space + 1)..].to_i?
      content = raw[(nul + 1)..]
      unless declared && declared == content.size
        raise ObjectError.new("loose object #{oid} size mismatch")
      end

      object = Object.new(type, content)
      unless object.oid == oid
        raise ObjectError.new("loose object id mismatch: stored as #{oid}, hashes to #{object.oid}")
      end
      object
    end

    private def path_for(oid : String) : String
      File.join(@objects_dir, oid[0, 2], oid[2..])
    end
  end
end
