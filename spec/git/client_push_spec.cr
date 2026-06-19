require "spec"
require "file_utils"
require "../../src/git/client"
require "./support/fake_session"
require "./support/fake_receive_pack"
require "./support/repo_fixture"

private CAPS = "report-status delete-refs side-band-64k ofs-delta agent=git/2.40"

private def with_repo(&)
  dir = File.tempname("crux-git-push", "")
  begin
    repo = Git::Repository.init(dir)
    yield repo
  ensure
    FileUtils.rm_rf(dir) if Dir.exists?(dir)
  end
end

# Writes a single-file commit into the repo's store and returns its oids.
private def add_commit(repo, content : String, parents : Array(String) = [] of String)
  blob = Git::Object.new(Git::ObjectType::Blob, content.to_slice)
  repo.store.write(blob)
  tree_bytes = RepoFixture.tree([{Git::TreeEntry::MODE_FILE, "file.txt", blob.oid}])
  tree = Git::Object.new(Git::ObjectType::Tree, tree_bytes)
  repo.store.write(tree)
  commit = Git::Object.new(Git::ObjectType::Commit, RepoFixture.commit(tree.oid, content, parents))
  repo.store.write(commit)
  {commit: commit.oid, tree: tree.oid, blob: blob.oid}
end

private def split_sent(sent : Bytes) : {Array(String), Bytes}
  io = IO::Memory.new(sent)
  reader = Git::PktLine::Reader.new(io)
  commands = [] of String
  reader.each_until_flush { |pkt| commands << pkt.text }
  rest = IO::Memory.new
  IO.copy(io, rest)
  {commands, rest.to_slice}
end

private def url
  Git::URL.parse("ssh://git@example.com/repo.git")
end

describe Git::Client do
  describe "#push" do
    it "pushes a new commit, sending only the missing objects" do
      with_repo do |repo|
        c1 = add_commit(repo, "v1\n")
        c2 = add_commit(repo, "v2\n", parents: [c1[:commit]])
        repo.write_ref("refs/heads/main", c2[:commit])
        repo.write_ref("refs/remotes/origin/main", c1[:commit])

        server = FakeReceivePack.build(
          [{c1[:commit], "refs/heads/main"}], CAPS,
          {"refs/heads/main" => nil}
        )
        transport = FakeTransport.new(server)

        report = Git::Client.new(transport, url).push_branch(repo, "main")
        report.ok?.should be_true

        commands, pack = split_sent(transport.session.sent.to_slice)
        commands.first.should start_with("#{c1[:commit]} #{c2[:commit]} refs/heads/main")

        sent_oids = Git::Pack::Reader.new(pack).objects.keys.to_set
        # Only c2's objects are sent; c1's are excluded (the remote has them).
        sent_oids.should eq([c2[:commit], c2[:tree], c2[:blob]].to_set)

        # Local remote-tracking ref advanced to the pushed tip.
        repo.read_ref("refs/remotes/origin/main").should eq(c2[:commit])
      end
    end

    it "refuses a non-fast-forward push without force" do
      with_repo do |repo|
        c1 = add_commit(repo, "base\n")
        divergent = add_commit(repo, "divergent\n") # no shared ancestry
        repo.write_ref("refs/heads/main", divergent[:commit])

        server = FakeReceivePack.build([{c1[:commit], "refs/heads/main"}], CAPS)
        expect_raises(Git::Error, /non-fast-forward/) do
          Git::Client.new(FakeTransport.new(server), url).push_branch(repo, "main")
        end
      end
    end

    it "allows a forced non-fast-forward push" do
      with_repo do |repo|
        c1 = add_commit(repo, "base\n")
        divergent = add_commit(repo, "divergent\n")
        repo.write_ref("refs/heads/main", divergent[:commit])

        server = FakeReceivePack.build(
          [{c1[:commit], "refs/heads/main"}], CAPS,
          {"refs/heads/main" => nil}
        )
        report = Git::Client.new(FakeTransport.new(server), url)
          .push(repo, [Git::Client::RefUpdate.update("refs/heads/main", force: true)])
        report.ok?.should be_true
      end
    end

    it "deletes a remote ref and drops the tracking ref, sending no pack" do
      with_repo do |repo|
        c1 = add_commit(repo, "v1\n")
        repo.write_ref("refs/heads/feature", c1[:commit])
        repo.write_ref("refs/remotes/origin/feature", c1[:commit])

        server = FakeReceivePack.build(
          [{c1[:commit], "refs/heads/feature"}], CAPS,
          {"refs/heads/feature" => nil}
        )
        transport = FakeTransport.new(server)

        report = Git::Client.new(transport, url)
          .push(repo, [Git::Client::RefUpdate.delete("refs/heads/feature")])
        report.ok?.should be_true

        _commands, pack = split_sent(transport.session.sent.to_slice)
        pack.should be_empty
        repo.read_ref("refs/remotes/origin/feature").should be_nil
      end
    end

    it "creates a branch on an empty remote" do
      with_repo do |repo|
        c1 = add_commit(repo, "first\n")
        repo.write_ref("refs/heads/main", c1[:commit])

        server = FakeReceivePack.build(
          Array({String, String}).new, CAPS,
          {"refs/heads/main" => nil}
        )
        transport = FakeTransport.new(server)

        report = Git::Client.new(transport, url).push_branch(repo, "main")
        report.ok?.should be_true

        commands, _pack = split_sent(transport.session.sent.to_slice)
        commands.first.should start_with("#{Git::Advertisement::NULL_OID} #{c1[:commit]} refs/heads/main")
        repo.read_ref("refs/remotes/origin/main").should eq(c1[:commit])
      end
    end

    it "raises when the local source ref is missing" do
      with_repo do |repo|
        server = FakeReceivePack.build(Array({String, String}).new, CAPS)
        expect_raises(Git::Error, /does not exist/) do
          Git::Client.new(FakeTransport.new(server), url).push_branch(repo, "nope")
        end
      end
    end
  end
end
