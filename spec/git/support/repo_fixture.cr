require "../../../src/git/object"

# Builds the raw byte forms of git tree and commit objects for tests, so the
# clone path can be exercised against a realistic object graph.
module RepoFixture
  # Serializes a tree from {mode, name, oid-hex} tuples.
  def self.tree(entries : Array({String, String, String})) : Bytes
    io = IO::Memory.new
    entries.sort_by { |(_, name, _)| name }.each do |(mode, name, oid)|
      io << mode << ' ' << name << Char::ZERO
      io.write(oid.hexbytes)
    end
    io.to_slice
  end

  # Serializes a commit pointing at `tree_oid` with optional parents.
  def self.commit(tree_oid : String, message : String, parents : Array(String) = [] of String) : Bytes
    io = IO::Memory.new
    io << "tree " << tree_oid << '\n'
    parents.each { |parent| io << "parent " << parent << '\n' }
    io << "author Test <test@example.com> 1700000000 +0000\n"
    io << "committer Test <test@example.com> 1700000000 +0000\n"
    io << '\n'
    io << message << '\n'
    io.to_slice
  end

  def self.oid(type : Git::ObjectType, content : String | Bytes) : String
    bytes = content.is_a?(String) ? content.to_slice : content
    Git::Object.new(type, bytes).oid
  end
end
