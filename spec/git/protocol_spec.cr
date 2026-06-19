require "spec"
require "../../src/git/protocol"
require "../../src/git/pack"
require "./support/fake_session"
require "./support/pack_builder"

private CAPS = "side-band-64k ofs-delta no-progress agent=git/2.40 symref=HEAD:refs/heads/main"

describe Git::UploadPackClient do
  it "discovers refs and downloads a side-band-muxed pack" do
    builder = PackBuilder.new
    blob_oid = builder.add(Git::ObjectType::Blob, "hello from the pack\n")
    pack = builder.build

    head = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    server = FakeUploadPack.build(
      [{head, "HEAD"}, {head, "refs/heads/main"}],
      CAPS, pack
    )

    session = FakeSession.new(server)
    client = Git::UploadPackClient.new(session)

    adv = client.discover
    adv.head_target.should eq("refs/heads/main")
    adv.reference("refs/heads/main").try(&.oid).should eq(head)

    downloaded = client.fetch([head])
    downloaded.should eq(pack)

    # The downloaded pack must parse back to the original object.
    objects = Git::Pack::Reader.new(downloaded).objects
    String.new(objects[blob_oid].data).should eq("hello from the pack\n")

    # Verify the client sent a well-formed request.
    sent = session.sent.to_s
    sent.should contain("want #{head} side-band-64k ofs-delta")
    sent.should contain("done")
  end

  it "negotiates only capabilities the server advertised" do
    pack = PackBuilder.new.tap(&.add(Git::ObjectType::Blob, "x")).build
    head = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    # Server offers neither side-band nor ofs-delta: pack is sent raw.
    server = build_raw_server([{head, "refs/heads/main"}], "agent=git/2.40", pack)

    session = FakeSession.new(server)
    client = Git::UploadPackClient.new(session)
    client.discover
    downloaded = client.fetch([head])
    downloaded.should eq(pack)

    sent = session.sent.to_s
    sent.should_not contain("side-band")
    sent.should_not contain("ofs-delta")
  end

  it "raises a RemoteError on a side-band channel 3 message" do
    head = "cccccccccccccccccccccccccccccccccccccccc"
    server = build_error_server([{head, "refs/heads/main"}], "side-band-64k", "fatal: bad object")

    client = Git::UploadPackClient.new(FakeSession.new(server))
    client.discover
    expect_raises(Git::RemoteError, /bad object/) do
      client.fetch([head])
    end
  end

  it "rejects a fetch with no wants" do
    server = FakeUploadPack.build([{"d" * 40, "refs/heads/main"}], CAPS, Bytes.empty)
    client = Git::UploadPackClient.new(FakeSession.new(server))
    client.discover
    expect_raises(Git::ProtocolError, /at least one want/) do
      client.fetch([] of String)
    end
  end
end

# Builds a server response with no side-band: advertisement, NAK, then the raw
# pack bytes appended directly.
private def build_raw_server(refs, caps, pack : Bytes) : Bytes
  io = IO::Memory.new
  writer = Git::PktLine::Writer.new(io)
  refs.each_with_index do |(oid, name), index|
    line = index.zero? ? "#{oid} #{name}#{Char::ZERO}#{caps}\n" : "#{oid} #{name}\n"
    writer.write(line)
  end
  writer.flush
  writer.write("NAK\n")
  io.write(pack)
  io.to_slice
end

# Builds a server that, instead of a pack, emits a fatal error on side-band
# channel 3.
private def build_error_server(refs, caps, message : String) : Bytes
  io = IO::Memory.new
  writer = Git::PktLine::Writer.new(io)
  refs.each_with_index do |(oid, name), index|
    line = index.zero? ? "#{oid} #{name}#{Char::ZERO}#{caps}\n" : "#{oid} #{name}\n"
    writer.write(line)
  end
  writer.flush
  writer.write("NAK\n")
  framed = Bytes.new(message.bytesize + 1)
  framed[0] = 3_u8
  message.to_slice.copy_to(framed + 1)
  writer.write(framed)
  writer.flush
  io.to_slice
end
