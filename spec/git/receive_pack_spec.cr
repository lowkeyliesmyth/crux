require "spec"
require "../../src/git/receive_pack"
require "../../src/git/pack"
require "./support/fake_session"
require "./support/fake_receive_pack"

private CAPS = "report-status delete-refs side-band-64k ofs-delta agent=git/2.40"
private OLD  = "1111111111111111111111111111111111111111"
private NEW  = "2222222222222222222222222222222222222222"

# Splits a captured client stream into its command lines and the trailing
# packfile (the raw bytes after the commands' flush-pkt).
private def split_sent(sent : Bytes) : {Array(String), Bytes}
  io = IO::Memory.new(sent)
  reader = Git::PktLine::Reader.new(io)
  commands = [] of String
  reader.each_until_flush { |pkt| commands << pkt.text }
  rest = IO::Memory.new
  IO.copy(io, rest)
  {commands, rest.to_slice}
end

describe Git::ReceivePackClient do
  it "sends commands and a pack, and parses an ok report" do
    server = FakeReceivePack.build(
      [{OLD, "refs/heads/main"}], CAPS,
      {"refs/heads/main" => nil}
    )
    session = FakeSession.new(server)
    client = Git::ReceivePackClient.new(session)

    client.discover.reference("refs/heads/main").try(&.oid).should eq(OLD)

    object = Git::Object.new(Git::ObjectType::Blob, "pushed\n".to_slice)
    report = client.send_update(
      [Git::PushCommand.new(OLD, NEW, "refs/heads/main")],
      [object]
    )

    report.ok?.should be_true
    report.unpack_ok?.should be_true

    commands, pack = split_sent(session.sent.to_slice)
    commands.first.should start_with("#{OLD} #{NEW} refs/heads/main")
    commands.first.should contain("report-status")

    # The trailing pack must contain exactly the object we pushed.
    objects = Git::Pack::Reader.new(pack).objects
    objects.has_key?(object.oid).should be_true
  end

  it "reports a rejected ref" do
    server = FakeReceivePack.build(
      [{OLD, "refs/heads/main"}], CAPS,
      {"refs/heads/main" => "non-fast-forward"}
    )
    client = Git::ReceivePackClient.new(FakeSession.new(server))
    client.discover

    report = client.send_update(
      [Git::PushCommand.new(OLD, NEW, "refs/heads/main")],
      [Git::Object.new(Git::ObjectType::Blob, "x".to_slice)]
    )

    report.ok?.should be_false
    report.rejected["refs/heads/main"].should eq("non-fast-forward")
  end

  it "reports an unpack failure" do
    server = FakeReceivePack.build(
      [{OLD, "refs/heads/main"}], CAPS,
      {"refs/heads/main" => nil}, unpack: "index-pack failed"
    )
    client = Git::ReceivePackClient.new(FakeSession.new(server))
    client.discover

    report = client.send_update(
      [Git::PushCommand.new(OLD, NEW, "refs/heads/main")],
      [Git::Object.new(Git::ObjectType::Blob, "x".to_slice)]
    )
    report.unpack_ok?.should be_false
    report.unpack_status.should eq("index-pack failed")
  end

  it "sends no pack for a delete-only push" do
    server = FakeReceivePack.build(
      [{OLD, "refs/heads/feature"}], CAPS,
      {"refs/heads/feature" => nil}
    )
    session = FakeSession.new(server)
    client = Git::ReceivePackClient.new(session)
    client.discover

    report = client.send_update(
      [Git::PushCommand.new(OLD, Git::Advertisement::NULL_OID, "refs/heads/feature")],
      [] of Git::Object
    )
    report.ok?.should be_true

    _commands, pack = split_sent(session.sent.to_slice)
    pack.should be_empty
  end

  it "creates a ref against an empty remote" do
    server = FakeReceivePack.build(
      Array({String, String}).new, CAPS,
      {"refs/heads/main" => nil}
    )
    session = FakeSession.new(server)
    client = Git::ReceivePackClient.new(session)
    adv = client.discover
    adv.references.should be_empty

    report = client.send_update(
      [Git::PushCommand.new(Git::Advertisement::NULL_OID, NEW, "refs/heads/main")],
      [Git::Object.new(Git::ObjectType::Blob, "first\n".to_slice)]
    )
    report.ok?.should be_true

    commands, _pack = split_sent(session.sent.to_slice)
    commands.first.should start_with("#{Git::Advertisement::NULL_OID} #{NEW} refs/heads/main")
  end
end
