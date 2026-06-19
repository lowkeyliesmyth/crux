require "digest/sha1"
require "./errors"

module Git
  # The four "real" object types plus the two delta encodings that may appear
  # inside a packfile. The integer values match the 3-bit type field used in
  # the packfile object header, so the enum can be decoded directly from it.
  enum ObjectType
    Commit   = 1
    Tree     = 2
    Blob     = 3
    Tag      = 4
    OfsDelta = 6
    RefDelta = 7

    # Returns the textual name git uses in the loose-object / hash header
    # (e.g. "blob"). Only valid for the four non-delta types.
    def loose_name : String
      case self
      in .commit? then "commit"
      in .tree?   then "tree"
      in .blob?   then "blob"
      in .tag?    then "tag"
      in .ofs_delta?, .ref_delta?
        raise PackError.new("delta objects have no loose name")
      end
    end

    # True for the delta encodings that must be resolved against a base object
    # before the real object is known.
    def delta? : Bool
      ofs_delta? || ref_delta?
    end

    # Parses a loose/header type word such as "commit".
    def self.from_loose_name(name : String) : ObjectType
      case name
      when "commit" then Commit
      when "tree"   then Tree
      when "blob"   then Blob
      when "tag"    then Tag
      else
        raise ObjectError.new("unknown object type #{name.inspect}")
      end
    end
  end

  # A fully resolved git object: a concrete type and its raw, uncompressed
  # content (without the loose-object header). Deltas are never represented
  # here -- by the time you hold an `Object` it has been resolved.
  struct Object
    getter type : ObjectType
    getter data : Bytes

    def initialize(@type : ObjectType, @data : Bytes)
      raise PackError.new("Object cannot hold a delta type") if @type.delta?
    end

    # The uncompressed byte length of the object content.
    def size : Int32
      @data.size
    end

    # The serialized loose-object header git prepends to content before hashing
    # and before zlib-deflating: the type name, a space, the decimal size, and
    # a terminating NUL byte.
    def header_bytes : Bytes
      io = IO::Memory.new
      io << @type.loose_name << ' ' << @data.size << '\0'
      io.to_slice
    end

    # The object id (SHA-1, lowercase hex) computed exactly as git does:
    # sha1(header + content).
    def oid : String
      digest = Digest::SHA1.new
      digest.update(header_bytes)
      digest.update(@data)
      digest.final.hexstring
    end

    # The serialized form git stores on disk before compression: header
    # followed by content.
    def to_loose : Bytes
      hdr = header_bytes
      buf = Bytes.new(hdr.size + @data.size)
      hdr.copy_to(buf)
      @data.copy_to(buf + hdr.size)
      buf
    end
  end
end
