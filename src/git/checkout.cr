require "./errors"
require "./object_store"
require "./tree"

module Git
  # Writes the contents of a tree object out to a working directory, recursing
  # into sub-trees. Reads every object from the given `ObjectStore`.
  class Checkout
    def initialize(@store : ObjectStore)
    end

    # Materializes `tree_oid` into `dir`, which must already exist.
    def materialize(tree_oid : String, dir : String) : Nil
      object = @store.read(tree_oid)
      raise ObjectError.new("missing tree object #{tree_oid}") unless object
      unless object.type.tree?
        raise ObjectError.new("object #{tree_oid} is a #{object.type}, not a tree")
      end

      Tree.parse(object.data).each do |entry|
        validate_name(entry.name)
        target = File.join(dir, entry.name)

        if entry.gitlink?
          # Submodule: record nothing on disk (no recursive clone yet).
          next
        elsif entry.tree?
          Dir.mkdir_p(target)
          materialize(entry.oid, target)
        elsif entry.symlink?
          write_symlink(entry.oid, target)
        else
          write_file(entry.oid, target, entry.executable?)
        end
      end
    end

    private def write_file(oid : String, target : String, executable : Bool) : Nil
      blob = read_blob(oid)
      File.write(target, blob.data)
      File.chmod(target, executable ? 0o755 : 0o644)
    end

    private def write_symlink(oid : String, target : String) : Nil
      blob = read_blob(oid)
      link_target = String.new(blob.data)
      File.delete(target) if File.exists?(target) || File.symlink?(target)
      File.symlink(link_target, target)
    end

    private def read_blob(oid : String) : Object
      object = @store.read(oid)
      raise ObjectError.new("missing blob object #{oid}") unless object
      unless object.type.blob?
        raise ObjectError.new("object #{oid} is a #{object.type}, not a blob")
      end
      object
    end

    # Guards against a hostile tree writing outside the target directory. Tree
    # entry names are single path components; anything with a separator, a
    # parent reference, or a NUL is rejected.
    private def validate_name(name : String) : Nil
      if name.empty? || name == "." || name == ".." ||
         name.includes?('/') || name.includes?('\\') || name.includes?(Char::ZERO)
        raise ObjectError.new("unsafe tree entry name #{name.inspect}")
      end
    end
  end
end
