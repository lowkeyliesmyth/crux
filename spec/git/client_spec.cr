require "spec"
require "file_utils"
require "../../src/git/client"
require "./support/fake_session"
require "./support/pack_builder"
require "./support/repo_fixture"

private CAPS = "side-band-64k ofs-delta no-progress symref=HEAD:refs/heads/main agent=git/2.40"

# Constructs an object graph (blob -> tree -> commit), packs it, and returns
# the pack together with the ids the test needs.
private def fixture_pack
  blob = "hello from clone\n"
  blob_oid = RepoFixture.oid(Git::ObjectType::Blob, blob)

  exec_blob = "#!/bin/sh\necho hi\n"
  exec_oid = RepoFixture.oid(Git::ObjectType::Blob, exec_blob)

  tree_bytes = RepoFixture.tree([
    {Git::TreeEntry::MODE_FILE, "README.md", blob_oid},
    {Git::TreeEntry::MODE_EXECUTABLE, "run.sh", exec_oid},
  ])
  tree_oid = RepoFixture.oid(Git::ObjectType::Tree, tree_bytes)

  commit_bytes = RepoFixture.commit(tree_oid, "initial commit")
  commit_oid = RepoFixture.oid(Git::ObjectType::Commit, commit_bytes)

  builder = PackBuilder.new
  builder.add(Git::ObjectType::Blob, blob)
  builder.add(Git::ObjectType::Blob, exec_blob)
  builder.add(Git::ObjectType::Tree, tree_bytes)
  builder.add(Git::ObjectType::Commit, commit_bytes)

  {pack: builder.build, commit: commit_oid, blob: blob, exec_blob: exec_blob}
end

private def with_tmp_dir(&)
  dir = File.tempname("crux-git-spec", "")
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir) if Dir.exists?(dir)
  end
end

describe Git::Client do
  describe "#clone_into" do
    it "clones a repository, writing refs, HEAD and the working tree" do
      fx = fixture_pack
      server = FakeUploadPack.build(
        [{fx[:commit], "HEAD"}, {fx[:commit], "refs/heads/main"}],
        CAPS, fx[:pack]
      )
      transport = FakeTransport.new(server)
      url = Git::URL.parse("ssh://git@example.com/team/repo.git")

      with_tmp_dir do |dir|
        repo = Git::Client.new(transport, url).clone_into(dir)

        # Working tree materialized.
        File.read(File.join(dir, "README.md")).should eq(fx[:blob])
        File.read(File.join(dir, "run.sh")).should eq(fx[:exec_blob])
        File.info(File.join(dir, "run.sh")).permissions.to_s.should contain("rwx")

        # Refs and HEAD set up.
        repo.head_target.should eq("refs/heads/main")
        repo.read_ref("refs/heads/main").should eq(fx[:commit])
        repo.read_ref("refs/remotes/origin/main").should eq(fx[:commit])

        # Objects landed in the loose store.
        repo.store.contains?(fx[:commit]).should be_true

        # Config records the remote.
        config = File.read(File.join(dir, ".git", "config"))
        config.should contain("[remote \"origin\"]")
        config.should contain("url = ssh://git@example.com/team/repo.git")

        # The client signalled it finished the session.
        transport.session.finished?.should be_true
      end
    end

    it "refuses to clone into an existing git directory" do
      fx = fixture_pack
      server = FakeUploadPack.build([{fx[:commit], "refs/heads/main"}], CAPS, fx[:pack])
      url = Git::URL.parse("ssh://git@example.com/repo.git")

      with_tmp_dir do |dir|
        Dir.mkdir_p(File.join(dir, ".git"))
        expect_raises(Git::Error, /already exists/) do
          Git::Client.new(FakeTransport.new(server), url).clone_into(dir)
        end
      end
    end

    it "lays down an empty repo when the remote has no refs" do
      # An empty-repo advertisement: a single capabilities^{} placeholder.
      empty = build_empty_advertisement
      url = Git::URL.parse("ssh://git@example.com/empty.git")

      with_tmp_dir do |dir|
        repo = Git::Client.new(FakeTransport.new(empty), url).clone_into(dir)
        Dir.exists?(repo.git_dir).should be_true
        repo.read_ref("refs/heads/main").should be_nil
      end
    end
  end
end

private def build_empty_advertisement : Bytes
  io = IO::Memory.new
  writer = Git::PktLine::Writer.new(io)
  writer.write("#{Git::Advertisement::NULL_OID} capabilities^{}#{Char::ZERO}#{CAPS}\n")
  writer.flush
  io.to_slice
end
