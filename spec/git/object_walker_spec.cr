require "spec"
require "file_utils"
require "../../src/git/object_walker"
require "../../src/git/object_store"
require "../../src/git/tree"
require "./support/repo_fixture"

private def with_store(&)
  dir = File.tempname("crux-git-walker", "")
  Dir.mkdir_p(dir)
  begin
    yield Git::ObjectStore.new(dir)
  ensure
    FileUtils.rm_rf(dir)
  end
end

# Writes a single-file commit into the store and returns the relevant oids.
private def write_commit(store, content : String, name : String, parents : Array(String) = [] of String)
  blob = Git::Object.new(Git::ObjectType::Blob, content.to_slice)
  store.write(blob)
  tree_bytes = RepoFixture.tree([{Git::TreeEntry::MODE_FILE, name, blob.oid}])
  tree = Git::Object.new(Git::ObjectType::Tree, tree_bytes)
  store.write(tree)
  commit_bytes = RepoFixture.commit(tree.oid, "commit #{content}", parents)
  commit = Git::Object.new(Git::ObjectType::Commit, commit_bytes)
  store.write(commit)
  {commit: commit.oid, tree: tree.oid, blob: blob.oid}
end

describe Git::ObjectWalker do
  it "collects the full closure of a tip with no excludes" do
    with_store do |store|
      c1 = write_commit(store, "v1\n", "file.txt")
      objects = Git::ObjectWalker.new(store).collect([c1[:commit]], [] of String)
      oids = objects.map(&.oid).to_set
      oids.should eq([c1[:commit], c1[:tree], c1[:blob]].to_set)
    end
  end

  it "excludes objects already reachable from the remote tip" do
    with_store do |store|
      c1 = write_commit(store, "v1\n", "file.txt")
      c2 = write_commit(store, "v2\n", "file.txt", parents: [c1[:commit]])

      objects = Git::ObjectWalker.new(store).collect([c2[:commit]], [c1[:commit]])
      oids = objects.map(&.oid).to_set

      # Only the new commit, its tree and its blob; nothing from c1.
      oids.should eq([c2[:commit], c2[:tree], c2[:blob]].to_set)
      oids.includes?(c1[:commit]).should be_false
      oids.includes?(c1[:blob]).should be_false
    end
  end

  it "returns nothing when the tip is already present on the remote" do
    with_store do |store|
      c1 = write_commit(store, "v1\n", "file.txt")
      Git::ObjectWalker.new(store).collect([c1[:commit]], [c1[:commit]]).should be_empty
    end
  end

  it "walks parent history when the remote has no refs" do
    with_store do |store|
      c1 = write_commit(store, "v1\n", "file.txt")
      c2 = write_commit(store, "v2\n", "file.txt", parents: [c1[:commit]])

      objects = Git::ObjectWalker.new(store).collect([c2[:commit]], [] of String)
      oids = objects.map(&.oid).to_set
      # Both commits and both blobs/trees are included.
      oids.includes?(c1[:commit]).should be_true
      oids.includes?(c2[:commit]).should be_true
      oids.size.should eq(6)
    end
  end
end
