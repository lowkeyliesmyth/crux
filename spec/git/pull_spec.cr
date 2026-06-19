require "spec"
require "file_utils"
require "../../src/git/client"
require "./support/fake_session"
require "./support/pack_builder"
require "./support/repo_fixture"

private CAPS = "side-band-64k ofs-delta no-progress symref=HEAD:refs/heads/main agent=git/2.40"

private def with_tmp_dir(&)
  dir = File.tempname("crux-git-pull", "")
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir) if Dir.exists?(dir)
  end
end

# Returns the pack and commit id for a single-file repo at version `content`,
# optionally with a parent commit (to model history).
private def commit_state(content : String, parents : Array(String) = [] of String)
  blob_oid = RepoFixture.oid(Git::ObjectType::Blob, content)
  tree_bytes = RepoFixture.tree([{Git::TreeEntry::MODE_FILE, "file.txt", blob_oid}])
  tree_oid = RepoFixture.oid(Git::ObjectType::Tree, tree_bytes)
  commit_bytes = RepoFixture.commit(tree_oid, "state #{content}", parents)
  commit_oid = RepoFixture.oid(Git::ObjectType::Commit, commit_bytes)

  builder = PackBuilder.new
  builder.add(Git::ObjectType::Blob, content)
  builder.add(Git::ObjectType::Tree, tree_bytes)
  builder.add(Git::ObjectType::Commit, commit_bytes)

  {pack: builder.build, commit: commit_oid, blob: content}
end

describe Git::Client do
  describe "#pull" do
    it "fast-forwards the current branch and updates the working tree" do
      v1 = commit_state("version one\n")
      v2 = commit_state("version two\n", parents: [v1[:commit]])
      url = Git::URL.parse("ssh://git@example.com/repo.git")

      with_tmp_dir do |dir|
        # Initial clone at v1.
        clone_server = FakeUploadPack.build(
          [{v1[:commit], "HEAD"}, {v1[:commit], "refs/heads/main"}], CAPS, v1[:pack]
        )
        repo = Git::Client.new(FakeTransport.new(clone_server), url).clone_into(dir)
        File.read(File.join(dir, "file.txt")).should eq("version one\n")

        # Remote advances to v2; pull should fast-forward.
        pull_server = FakeUploadPack.build(
          [{v2[:commit], "HEAD"}, {v2[:commit], "refs/heads/main"}], CAPS, v2[:pack]
        )
        result = Git::Client.new(FakeTransport.new(pull_server), url).pull(repo)

        File.read(File.join(dir, "file.txt")).should eq("version two\n")
        repo.read_ref("refs/heads/main").should eq(v2[:commit])
        repo.read_ref("refs/remotes/origin/main").should eq(v2[:commit])
        result.updated.has_key?("refs/remotes/origin/main").should be_true
      end
    end

    it "is a no-op when already up to date" do
      v1 = commit_state("only version\n")
      url = Git::URL.parse("ssh://git@example.com/repo.git")

      with_tmp_dir do |dir|
        server = FakeUploadPack.build(
          [{v1[:commit], "HEAD"}, {v1[:commit], "refs/heads/main"}], CAPS, v1[:pack]
        )
        repo = Git::Client.new(FakeTransport.new(server), url).clone_into(dir)

        same = FakeUploadPack.build(
          [{v1[:commit], "HEAD"}, {v1[:commit], "refs/heads/main"}], CAPS, Bytes.empty
        )
        result = Git::Client.new(FakeTransport.new(same), url).pull(repo)

        result.objects_written.should eq(0)
        result.updated.should be_empty
      end
    end

    it "refuses a non-fast-forward update" do
      v1 = commit_state("base\n")
      # A divergent commit with no shared ancestry.
      other = commit_state("divergent\n")
      url = Git::URL.parse("ssh://git@example.com/repo.git")

      with_tmp_dir do |dir|
        server = FakeUploadPack.build(
          [{v1[:commit], "HEAD"}, {v1[:commit], "refs/heads/main"}], CAPS, v1[:pack]
        )
        repo = Git::Client.new(FakeTransport.new(server), url).clone_into(dir)

        diverged = FakeUploadPack.build(
          [{other[:commit], "HEAD"}, {other[:commit], "refs/heads/main"}], CAPS, other[:pack]
        )
        expect_raises(Git::Error, /non-fast-forward/) do
          Git::Client.new(FakeTransport.new(diverged), url).pull(repo)
        end
      end
    end
  end
end
