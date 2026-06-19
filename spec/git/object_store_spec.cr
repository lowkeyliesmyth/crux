require "spec"
require "file_utils"
require "../../src/git/object_store"

private def with_store(&)
  dir = File.tempname("crux-git-store", "")
  Dir.mkdir_p(dir)
  begin
    yield Git::ObjectStore.new(dir), dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe Git::ObjectStore do
  it "writes and reads back a loose object" do
    with_store do |store, _|
      object = Git::Object.new(Git::ObjectType::Blob, "round trip\n".to_slice)
      oid = store.write(object)

      store.contains?(oid).should be_true
      read = store.read(oid)
      read.should be_a(Git::Object)
      if read
        read.type.blob?.should be_true
        String.new(read.data).should eq("round trip\n")
      end
    end
  end

  it "stores objects under a fanout directory named by the id prefix" do
    with_store do |store, dir|
      oid = store.write(Git::Object.new(Git::ObjectType::Blob, "x".to_slice))
      File.exists?(File.join(dir, oid[0, 2], oid[2..])).should be_true
    end
  end

  it "returns nil for an unknown object" do
    with_store do |store, _|
      store.read("0" * 40).should be_nil
      store.contains?("0" * 40).should be_false
    end
  end

  it "is idempotent and does not rewrite an existing object" do
    with_store do |store, _|
      object = Git::Object.new(Git::ObjectType::Blob, "same".to_slice)
      first = store.write(object)
      second = store.write(object)
      first.should eq(second)
    end
  end

  it "exposes a base_lookup proc for thin-pack resolution" do
    with_store do |store, _|
      object = Git::Object.new(Git::ObjectType::Blob, "base".to_slice)
      oid = store.write(object)
      store.base_lookup.call(oid).try(&.oid).should eq(oid)
      store.base_lookup.call("0" * 40).should be_nil
    end
  end

  it "detects a corrupted loose object" do
    with_store do |store, dir|
      oid = store.write(Git::Object.new(Git::ObjectType::Blob, "intact".to_slice))
      path = File.join(dir, oid[0, 2], oid[2..])
      File.write(path, "not a valid zlib stream")
      expect_raises(Exception) { store.read(oid) }
    end
  end
end
