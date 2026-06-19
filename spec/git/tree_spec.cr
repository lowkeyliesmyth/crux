require "spec"
require "../../src/git/tree"
require "../../src/git/object"

# Builds a tree object body from {mode, name, oid-hex} entries.
private def tree_bytes(entries : Array({String, String, String})) : Bytes
  io = IO::Memory.new
  entries.each do |(mode, name, oid)|
    io << mode << ' ' << name << Char::ZERO
    io.write(oid.hexbytes)
  end
  io.to_slice
end

private OID_A = "1111111111111111111111111111111111111111"
private OID_B = "2222222222222222222222222222222222222222"

describe Git::Tree do
  it "parses entries of mixed modes" do
    data = tree_bytes([
      {Git::TreeEntry::MODE_FILE, "README.md", OID_A},
      {Git::TreeEntry::MODE_DIR, "src", OID_B},
    ])

    entries = Git::Tree.parse(data)
    entries.size.should eq(2)

    entries[0].name.should eq("README.md")
    entries[0].oid.should eq(OID_A)
    entries[0].tree?.should be_false

    entries[1].name.should eq("src")
    entries[1].tree?.should be_true
    entries[1].oid.should eq(OID_B)
  end

  it "recognises executable, symlink and gitlink modes" do
    data = tree_bytes([
      {Git::TreeEntry::MODE_EXECUTABLE, "run", OID_A},
      {Git::TreeEntry::MODE_SYMLINK, "link", OID_A},
      {Git::TreeEntry::MODE_GITLINK, "sub", OID_B},
    ])
    entries = Git::Tree.parse(data)
    entries[0].executable?.should be_true
    entries[1].symlink?.should be_true
    entries[2].gitlink?.should be_true
  end

  it "raises on a truncated entry" do
    expect_raises(Git::ObjectError) do
      Git::Tree.parse("100644 file".to_slice)
    end
  end
end

describe Git::Commit do
  it "parses the tree and parents from a commit header" do
    body = String.build do |io|
      io << "tree " << OID_A << '\n'
      io << "parent " << OID_B << '\n'
      io << "author A <a@x> 1 +0000\n"
      io << "committer A <a@x> 1 +0000\n"
      io << '\n'
      io << "message body\n"
    end

    commit = Git::Commit.parse(body.to_slice)
    commit.tree.should eq(OID_A)
    commit.parents.should eq([OID_B])
  end

  it "raises when the tree header is missing" do
    expect_raises(Git::ObjectError, /no tree/) do
      Git::Commit.parse("author A <a@x> 1 +0000\n\nbody\n".to_slice)
    end
  end
end
