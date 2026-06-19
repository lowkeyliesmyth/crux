require "./errors"
require "./object"
require "./object_store"
require "./tree"

module Git
  # Computes the set of objects that must be sent to a remote: everything
  # reachable from the pushed tips that the remote does not already have.
  #
  # The remote is assumed to hold the full closure of any ref it advertises
  # (true for a well-formed repository), so the objects reachable from the
  # advertised tips are treated as "already present" and excluded. The walk
  # reads every object from the local store; objects missing locally (e.g. a
  # remote-only branch we never fetched) simply terminate that branch of the
  # traversal, which at worst makes the push send a few redundant objects.
  class ObjectWalker
    def initialize(@store : ObjectStore)
    end

    # Returns the objects reachable from `tips` but not from `excludes`. Order
    # is unspecified (irrelevant for a non-delta pack).
    def collect(tips : Enumerable(String), excludes : Enumerable(String)) : Array(Object)
      have = reachable_oids(excludes)

      result = [] of Object
      seen = Set(String).new
      commit_queue = tips.to_a
      visited = Set(String).new

      until commit_queue.empty?
        oid = commit_queue.shift
        next unless visited.add?(oid)
        next if have.includes?(oid)

        object = @store.read(oid)
        next unless object

        case object.type
        when .commit?
          add(object, result, seen, have)
          commit = Commit.parse(object.data)
          add_tree(commit.tree, result, seen, have)
          commit.parents.each { |parent| commit_queue << parent }
        when .tag?
          add(object, result, seen, have)
          if target = tag_target(object)
            commit_queue << target
          end
        when .tree?
          add_tree(oid, result, seen, have)
        when .blob?
          add(object, result, seen, have)
        end
      end

      result
    end

    # Walks the full object closure of `roots` into a set of object ids.
    private def reachable_oids(roots : Enumerable(String)) : Set(String)
      oids = Set(String).new
      commit_queue = roots.to_a
      visited = Set(String).new

      until commit_queue.empty?
        oid = commit_queue.shift
        next unless visited.add?(oid)
        next if oids.includes?(oid)

        object = @store.read(oid)
        next unless object

        case object.type
        when .commit?
          oids << oid
          commit = Commit.parse(object.data)
          mark_tree(commit.tree, oids)
          commit.parents.each { |parent| commit_queue << parent }
        when .tag?
          oids << oid
          if target = tag_target(object)
            commit_queue << target
          end
        when .tree?
          mark_tree(oid, oids)
        when .blob?
          oids << oid
        end
      end

      oids
    end

    # Adds an object (and recursively a tree's contents) to a marker set.
    private def mark_tree(tree_oid : String, oids : Set(String)) : Nil
      return if oids.includes?(tree_oid)
      object = @store.read(tree_oid)
      return unless object && object.type.tree?

      oids << tree_oid
      Tree.parse(object.data).each do |entry|
        next if entry.gitlink?
        if entry.tree?
          mark_tree(entry.oid, oids)
        else
          oids << entry.oid
        end
      end
    end

    # Collects an object into the send list, honouring the have-set and dedup.
    private def add(object : Object, result : Array(Object), seen : Set(String), have : Set(String)) : Nil
      oid = object.oid
      return if have.includes?(oid)
      return unless seen.add?(oid)
      result << object
    end

    # Recursively collects a tree and its blobs/sub-trees into the send list.
    private def add_tree(tree_oid : String, result : Array(Object), seen : Set(String), have : Set(String)) : Nil
      return if have.includes?(tree_oid) || seen.includes?(tree_oid)
      object = @store.read(tree_oid)
      return unless object && object.type.tree?

      add(object, result, seen, have)
      Tree.parse(object.data).each do |entry|
        next if entry.gitlink?
        if entry.tree?
          add_tree(entry.oid, result, seen, have)
        elsif blob = @store.read(entry.oid)
          add(blob, result, seen, have)
        end
      end
    end

    # Reads the target object id from an annotated tag's `object` header.
    private def tag_target(tag : Object) : String?
      String.new(tag.data).each_line do |line|
        break if line.empty?
        return line.lchop("object ").strip if line.starts_with?("object ")
      end
      nil
    end
  end
end
