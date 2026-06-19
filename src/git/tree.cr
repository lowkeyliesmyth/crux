require "./errors"

module Git
  # One entry in a git tree object: a file mode, a name, and the id of the
  # object (blob or sub-tree) it points to.
  struct TreeEntry
    # Common git file modes.
    MODE_DIR        = "40000"
    MODE_FILE       = "100644"
    MODE_EXECUTABLE = "100755"
    MODE_SYMLINK    = "120000"
    MODE_GITLINK    = "160000"

    getter mode : String
    getter name : String
    getter oid : String

    def initialize(@mode, @name, @oid)
    end

    def tree? : Bool
      @mode == MODE_DIR
    end

    def executable? : Bool
      @mode == MODE_EXECUTABLE
    end

    def symlink? : Bool
      @mode == MODE_SYMLINK
    end

    # A submodule reference (gitlink); has no content to materialize.
    def gitlink? : Bool
      @mode == MODE_GITLINK
    end
  end

  # Parses git tree objects. The serialized form is a flat sequence of
  # `"<mode> <name>\0<20-byte-binary-oid>"` records, sorted by name.
  module Tree
    def self.parse(data : Bytes) : Array(TreeEntry)
      entries = [] of TreeEntry
      pos = 0
      while pos < data.size
        space = index_of(data, ' '.ord.to_u8, pos)
        raise ObjectError.new("tree entry missing mode separator") unless space
        mode = String.new(data[pos...space])

        nul = index_of(data, 0_u8, space + 1)
        raise ObjectError.new("tree entry missing name terminator") unless nul
        name = String.new(data[(space + 1)...nul])

        oid_start = nul + 1
        if oid_start + 20 > data.size
          raise ObjectError.new("tree entry has a truncated object id")
        end
        oid = data[oid_start, 20].hexstring
        entries << TreeEntry.new(mode, name, oid)
        pos = oid_start + 20
      end
      entries
    end

    private def self.index_of(data : Bytes, byte : UInt8, from : Int32) : Int32?
      i = from
      while i < data.size
        return i if data[i] == byte
        i += 1
      end
      nil
    end
  end

  # Parses the header of a git commit object -- enough to follow history and
  # find the root tree. The body/message is not needed here.
  struct Commit
    getter tree : String
    getter parents : Array(String)

    def initialize(@tree, @parents)
    end

    def self.parse(data : Bytes) : Commit
      tree = nil
      parents = [] of String

      String.new(data).each_line do |line|
        break if line.empty? # blank line terminates the header
        if line.starts_with?("tree ")
          tree = line.lchop("tree ").strip
        elsif line.starts_with?("parent ")
          parents << line.lchop("parent ").strip
        end
      end

      raise ObjectError.new("commit object has no tree") unless tree
      new(tree, parents)
    end
  end
end
