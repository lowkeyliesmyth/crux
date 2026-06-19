require "spec"
require "../../src/git/pack"
require "./support/pack_builder"

describe Git::Pack::Reader do
  it "reads multiple non-delta objects of different types" do
    builder = PackBuilder.new
    blob_oid = builder.add(Git::ObjectType::Blob, "hello\n")
    tree_content = Bytes[0x31, 0x32, 0x33] # arbitrary bytes
    tree_oid = builder.add(Git::ObjectType::Tree, tree_content)

    objects = Git::Pack::Reader.new(builder.build).objects

    objects.size.should eq(2)
    objects[blob_oid].type.blob?.should be_true
    String.new(objects[blob_oid].data).should eq("hello\n")
    objects[tree_oid].type.tree?.should be_true
  end

  it "resolves a REF_DELTA against an in-pack base" do
    builder = PackBuilder.new
    base_oid = builder.add(Git::ObjectType::Blob, "hello\n")
    # source size 6, target size 7: COPY [0,5] "hello" + INSERT "!\n"
    delta = Bytes[0x06, 0x07, 0x90, 0x05, 0x02, '!'.ord, '\n'.ord]
    builder.add_ref_delta(base_oid, delta)

    objects = Git::Pack::Reader.new(builder.build).objects

    expected = Git::Object.new(Git::ObjectType::Blob, "hello!\n".to_slice)
    objects.has_key?(expected.oid).should be_true
    String.new(objects[expected.oid].data).should eq("hello!\n")
  end

  it "resolves an OFS_DELTA against an earlier object" do
    builder = PackBuilder.new
    builder.add(Git::ObjectType::Blob, "abcdefgh")
    # source size 8, target size 9: COPY [0,8] + INSERT "X"
    delta = Bytes[0x08, 0x09, 0x90, 0x08, 0x01, 'X'.ord]
    builder.add_ofs_delta(0, delta)

    objects = Git::Pack::Reader.new(builder.build).objects

    expected = Git::Object.new(Git::ObjectType::Blob, "abcdefghX".to_slice)
    String.new(objects[expected.oid].data).should eq("abcdefghX")
  end

  it "resolves a chained delta (delta of a delta)" do
    builder = PackBuilder.new
    builder.add(Git::ObjectType::Blob, "abcdefgh")
    delta1 = Bytes[0x08, 0x09, 0x90, 0x08, 0x01, 'X'.ord] # -> "abcdefghX"
    builder.add_ofs_delta(0, delta1)
    # delta of the previous object: source 9, target 10: COPY[0,9] + INSERT "Y"
    delta2 = Bytes[0x09, 0x0a, 0x90, 0x09, 0x01, 'Y'.ord]
    builder.add_ofs_delta(1, delta2)

    objects = Git::Pack::Reader.new(builder.build).objects

    expected = Git::Object.new(Git::ObjectType::Blob, "abcdefghXY".to_slice)
    String.new(objects[expected.oid].data).should eq("abcdefghXY")
  end

  it "handles an empty object" do
    builder = PackBuilder.new
    oid = builder.add(Git::ObjectType::Blob, "")
    objects = Git::Pack::Reader.new(builder.build).objects
    objects[oid].size.should eq(0)
  end

  it "consults the external base lookup for a missing REF_DELTA base (thin pack)" do
    external = Git::Object.new(Git::ObjectType::Blob, "hello\n".to_slice)
    builder = PackBuilder.new
    delta = Bytes[0x06, 0x07, 0x90, 0x05, 0x02, '!'.ord, '\n'.ord]
    builder.add_ref_delta(external.oid, delta)

    lookup = ->(oid : String) { oid == external.oid ? external : nil }
    objects = Git::Pack::Reader.new(builder.build, lookup).objects

    expected = Git::Object.new(Git::ObjectType::Blob, "hello!\n".to_slice)
    objects.has_key?(expected.oid).should be_true
  end

  it "raises when a delta base is missing" do
    builder = PackBuilder.new
    delta = Bytes[0x06, 0x07, 0x90, 0x05, 0x02, '!'.ord, '\n'.ord]
    builder.add_ref_delta("0" * 40, delta)
    expect_raises(Git::ObjectError, /cannot resolve delta base/) do
      Git::Pack::Reader.new(builder.build).objects
    end
  end

  it "raises on a bad checksum" do
    builder = PackBuilder.new
    builder.add(Git::ObjectType::Blob, "hello\n")
    data = builder.build
    data[data.size - 1] ^= 0xff # corrupt the trailer
    expect_raises(Git::PackError, /checksum mismatch/) do
      Git::Pack::Reader.new(data).objects
    end
  end

  it "raises on a bad signature" do
    bytes = Bytes.new(40)
    "NOPE".to_slice.copy_to(bytes)
    expect_raises(Git::PackError) { Git::Pack::Reader.new(bytes).objects }
  end
end
