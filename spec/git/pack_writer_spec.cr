require "spec"
require "../../src/git/pack_writer"
require "../../src/git/pack"
require "../../src/git/tree"
require "./support/repo_fixture"

describe Git::Pack::Writer do
  it "round-trips objects through writer and reader" do
    blob = Git::Object.new(Git::ObjectType::Blob, "hello\n".to_slice)
    tree_bytes = RepoFixture.tree([{Git::TreeEntry::MODE_FILE, "README.md", blob.oid}])
    tree = Git::Object.new(Git::ObjectType::Tree, tree_bytes)
    commit_bytes = RepoFixture.commit(tree.oid, "initial")
    commit = Git::Object.new(Git::ObjectType::Commit, commit_bytes)

    pack = Git::Pack::Writer.build([blob, tree, commit])
    pack[0, 4].should eq("PACK".to_slice)

    objects = Git::Pack::Reader.new(pack).objects
    objects.size.should eq(3)
    String.new(objects[blob.oid].data).should eq("hello\n")
    objects[tree.oid].type.tree?.should be_true
    objects[commit.oid].type.commit?.should be_true
  end

  it "writes a valid empty (zero-object) pack" do
    pack = Git::Pack::Writer.build([] of Git::Object)
    Git::Pack::Reader.new(pack).objects.should be_empty
  end

  it "preserves large object content across the size varint boundary" do
    big = Bytes.new(100_000) { |i| (i % 251).to_u8 }
    object = Git::Object.new(Git::ObjectType::Blob, big)

    pack = Git::Pack::Writer.build([object])
    objects = Git::Pack::Reader.new(pack).objects
    objects[object.oid].data.should eq(big)
  end
end
