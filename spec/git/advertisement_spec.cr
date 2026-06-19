require "spec"
require "../../src/git/advertisement"

# Builds a v0 ref-advertisement byte stream from the given lines, framing each
# as a pkt-line and terminating with a flush. NUL separators are written via
# Char::ZERO to keep raw NULs out of the source.
private def advertise(lines : Array(String)) : IO::Memory
  io = IO::Memory.new
  writer = Git::PktLine::Writer.new(io)
  lines.each { |line| writer.write("#{line}\n") }
  writer.flush
  io.rewind
  io
end

private OID_MAIN = "1111111111111111111111111111111111111111"
private OID_DEV  = "2222222222222222222222222222222222222222"

describe Git::Advertisement do
  it "parses refs, capabilities and the HEAD symref" do
    caps = "multi_ack_detailed side-band-64k ofs-delta symref=HEAD:refs/heads/main agent=git/2.40"
    io = advertise([
      "#{OID_MAIN} HEAD#{Char::ZERO}#{caps}",
      "#{OID_MAIN} refs/heads/main",
      "#{OID_DEV} refs/heads/dev",
    ])

    adv = Git::Advertisement.read(Git::PktLine::Reader.new(io))

    adv.references.map(&.name).should eq(["HEAD", "refs/heads/main", "refs/heads/dev"])
    adv.reference("refs/heads/dev").try(&.oid).should eq(OID_DEV)
    adv.capabilities.supports?("ofs-delta").should be_true
    adv.capabilities.supports?("side-band-64k").should be_true
    adv.capabilities.value("agent").should eq("git/2.40")
    adv.head_target.should eq("refs/heads/main")
    adv.head_oid.should eq(OID_MAIN)
  end

  it "treats an empty repository advertisement as having no references" do
    io = advertise(["#{Git::Advertisement::NULL_OID} capabilities^{}#{Char::ZERO}agent=git/2.40"])
    adv = Git::Advertisement.read(Git::PktLine::Reader.new(io))
    adv.references.should be_empty
    adv.head_oid.should be_nil
    adv.capabilities.value("agent").should eq("git/2.40")
  end

  it "raises a RemoteError on an ERR line" do
    io = advertise(["ERR access denied or repository not exported"])
    expect_raises(Git::RemoteError, /access denied/) do
      Git::Advertisement.read(Git::PktLine::Reader.new(io))
    end
  end

  it "falls back to an explicit HEAD entry when no symref is advertised" do
    io = advertise([
      "#{OID_MAIN} HEAD#{Char::ZERO}ofs-delta",
      "#{OID_MAIN} refs/heads/main",
    ])
    adv = Git::Advertisement.read(Git::PktLine::Reader.new(io))
    adv.head_target.should be_nil
    adv.head_oid.should eq(OID_MAIN)
  end
end
