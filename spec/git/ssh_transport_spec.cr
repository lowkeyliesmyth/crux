require "spec"
require "file_utils"
require "../../src/git/client"
require "./support/pack_builder"
require "./support/fake_session"
require "./support/repo_fixture"

private CAPS = "side-band-64k ofs-delta no-progress symref=HEAD:refs/heads/main agent=git/2.40"

# Writes a fake `ssh` executable that records the argv it was invoked with,
# streams a canned upload-pack response to stdout, and then drains stdin. This
# lets us drive the real SSHTransport/ProcessSession code path (subprocess
# spawn + pipes) without a network or a real git server.
private def fake_ssh(response_path : String, args_path : String) : String
  path = File.tempname("fake-ssh", ".sh")
  File.write(path, <<-SH)
  #!/bin/sh
  printf '%s\\n' "$@" > "#{args_path}"
  cat "#{response_path}"
  cat > /dev/null
  SH
  File.chmod(path, 0o755)
  path
end

describe Git::SSHTransport do
  it "clones through the real subprocess transport" do
    fx_blob = "via real ssh subprocess\n"
    blob_oid = RepoFixture.oid(Git::ObjectType::Blob, fx_blob)
    tree_bytes = RepoFixture.tree([{Git::TreeEntry::MODE_FILE, "file.txt", blob_oid}])
    tree_oid = RepoFixture.oid(Git::ObjectType::Tree, tree_bytes)
    commit_bytes = RepoFixture.commit(tree_oid, "real ssh")
    commit_oid = RepoFixture.oid(Git::ObjectType::Commit, commit_bytes)

    builder = PackBuilder.new
    builder.add(Git::ObjectType::Blob, fx_blob)
    builder.add(Git::ObjectType::Tree, tree_bytes)
    builder.add(Git::ObjectType::Commit, commit_bytes)
    pack = builder.build

    response = FakeUploadPack.build(
      [{commit_oid, "HEAD"}, {commit_oid, "refs/heads/main"}], CAPS, pack
    )

    response_path = File.tempname("ssh-response", ".bin")
    args_path = File.tempname("ssh-args", ".txt")
    File.write(response_path, response)
    ssh = fake_ssh(response_path, args_path)

    url = Git::URL.parse("ssh://git@example.com:2222/team/repo.git")
    transport = Git::SSHTransport.new(url, ssh_command: ssh)

    dir = File.tempname("crux-ssh-clone", "")
    begin
      repo = Git::Client.new(transport, url).clone_into(dir)

      File.read(File.join(dir, "file.txt")).should eq(fx_blob)
      repo.read_ref("refs/heads/main").should eq(commit_oid)

      # The transport built the expected remote command and ssh options.
      argv = File.read(args_path)
      argv.should contain("-p")
      argv.should contain("2222")
      argv.should contain("git@example.com")
      argv.should contain("git-upload-pack '/team/repo.git'")
    ensure
      FileUtils.rm_rf(dir) if Dir.exists?(dir)
      File.delete(response_path) if File.exists?(response_path)
      File.delete(args_path) if File.exists?(args_path)
      File.delete(ssh) if File.exists?(ssh)
    end
  end
end
