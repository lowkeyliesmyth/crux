require "./errors"
require "./url"
require "./transport"
require "./protocol"
require "./pack"
require "./repository"
require "./advertisement"

module Git
  # High-level porcelain: clone a remote, or fetch/pull into an existing local
  # repository, over SSH. Orchestrates the transport, the upload-pack
  # conversation, pack resolution, ref bookkeeping and checkout.
  #
  # The `Transport` is injectable so the orchestration can be tested against an
  # in-memory fake; the convenience constructors wire up a real `SSHTransport`.
  class Client
    DEFAULT_REMOTE = "origin"

    # The outcome of a fetch: which remote-tracking refs changed and the new
    # object count written to the store.
    record FetchResult,
      updated : Hash(String, String),
      objects_written : Int32

    getter url : URL
    property remote_name : String
    property progress : IO?

    def initialize(@transport : Transport, @url : URL, @remote_name : String = DEFAULT_REMOTE)
    end

    # Builds a client whose transport invokes the system ssh client.
    def self.for(remote : String, ssh_command : String = "ssh", ssh_options : Array(String) = [] of String) : Client
      url = URL.parse(remote)
      new(SSHTransport.new(url, ssh_command, ssh_options), url)
    end

    # Clones the remote into a new `dir`, returning the populated `Repository`.
    def self.clone(remote : String, dir : String, progress : IO? = nil) : Repository
      client = self.for(remote)
      client.progress = progress
      client.clone_into(dir)
    end

    # Clones into `dir`: discovers refs, downloads every branch and tag,
    # writes remote-tracking refs plus the default local branch, and checks the
    # default branch out into the working tree.
    def clone_into(dir : String) : Repository
      session = @transport.upload_pack
      begin
        upload = UploadPackClient.new(session)
        upload.progress = @progress
        advertisement = upload.discover

        if advertisement.references.empty?
          session.finish
          return empty_clone(dir, advertisement)
        end

        repo = Repository.init(dir)
        wants = clone_wants(advertisement)
        pack = upload.fetch(wants)
        session.finish

        store_pack(repo, pack)
        update_remote_tracking(repo, advertisement)
        write_tags(repo, advertisement)
        finalize_head(repo, advertisement)
        repo.write_config(@remote_name, @url.to_s, default_branch_name(advertisement))
        repo
      rescue ex
        session.abort
        raise ex
      end
    end

    # Fetches updates into an existing repository, updating remote-tracking
    # refs and tags. Does not touch local branches or the working tree.
    def fetch(repo : Repository) : FetchResult
      session = @transport.upload_pack
      begin
        upload = UploadPackClient.new(session)
        upload.progress = @progress
        advertisement = upload.discover

        wants = fetch_wants(repo, advertisement)
        if wants.empty?
          session.finish
          return FetchResult.new({} of String => String, 0)
        end

        haves = local_haves(repo)
        pack = upload.fetch(wants, haves)
        session.finish

        written = store_pack(repo, pack)
        updated = update_remote_tracking(repo, advertisement)
        write_tags(repo, advertisement)
        FetchResult.new(updated, written)
      rescue ex
        session.abort
        raise ex
      end
    end

    # Fetches, then fast-forwards the currently checked-out branch to its
    # upstream remote-tracking ref and updates the working tree. Raises if the
    # update is not a fast-forward (merges are out of scope).
    def pull(repo : Repository) : FetchResult
      result = fetch(repo)

      branch_ref = repo.head_target
      raise Error.new("cannot pull with a detached HEAD") unless branch_ref
      branch = branch_ref.lchop("refs/heads/")

      remote_ref = "refs/remotes/#{@remote_name}/#{branch}"
      remote_tip = repo.read_ref(remote_ref)
      raise Error.new("no upstream #{remote_ref} for branch #{branch}") unless remote_tip

      local_tip = repo.read_ref(branch_ref)
      if local_tip.nil? || local_tip == remote_tip
        repo.write_ref(branch_ref, remote_tip)
        repo.checkout(remote_tip)
      elsif repo.ancestor?(local_tip, remote_tip)
        repo.write_ref(branch_ref, remote_tip)
        repo.checkout(remote_tip)
      else
        raise Error.new("non-fast-forward: #{branch} has diverged from #{@remote_name} (merge not supported)")
      end

      result
    end

    # Resolves and stores every object in a pack, using the repo's existing
    # objects to satisfy thin-pack delta bases.
    private def store_pack(repo : Repository, pack : Bytes) : Int32
      return 0 if pack.empty?
      objects = Pack::Reader.new(pack, repo.store.base_lookup).objects
      repo.store_objects(objects.values)
    end

    # For a clone, we want every branch and tag tip.
    private def clone_wants(advertisement : Advertisement) : Array(String)
      wantable_oids(advertisement.references)
    end

    # For a fetch, we want only branch/tag tips we do not already have.
    private def fetch_wants(repo : Repository, advertisement : Advertisement) : Array(String)
      wantable_oids(advertisement.references).reject { |oid| repo.store.contains?(oid) }
    end

    private def wantable_oids(references : Array(Reference)) : Array(String)
      references
        .reject(&.peeled?)
        .map(&.oid)
        .reject { |oid| oid == Advertisement::NULL_OID }
        .uniq!
    end

    # Object ids the server may assume we already have (our local ref tips).
    private def local_haves(repo : Repository) : Array(String)
      haves = [] of String
      ["heads", "remotes", "tags"].each do |kind|
        dir = File.join(repo.git_dir, "refs", kind)
        next unless Dir.exists?(dir)
        collect_ref_oids(repo, "refs/#{kind}", dir, haves)
      end
      haves.uniq
    end

    private def collect_ref_oids(repo : Repository, prefix : String, dir : String, into : Array(String)) : Nil
      Dir.each_child(dir) do |child|
        full = File.join(dir, child)
        if File.directory?(full)
          collect_ref_oids(repo, "#{prefix}/#{child}", full, into)
        elsif oid = repo.read_ref("#{prefix}/#{child}")
          into << oid
        end
      end
    end

    # Writes refs/remotes/<remote>/<branch> for each advertised branch,
    # returning the refs whose value changed.
    private def update_remote_tracking(repo : Repository, advertisement : Advertisement) : Hash(String, String)
      updated = {} of String => String
      advertisement.references.each do |ref|
        next unless name = ref.branch_name
        tracking = "refs/remotes/#{@remote_name}/#{name}"
        if repo.read_ref(tracking) != ref.oid
          repo.write_ref(tracking, ref.oid)
          updated[tracking] = ref.oid
        end
      end
      updated
    end

    # Mirrors advertised tags into refs/tags/<name>. Peeled entries are skipped;
    # the tag object id is what we record.
    private def write_tags(repo : Repository, advertisement : Advertisement) : Nil
      advertisement.references.each do |ref|
        next unless ref.name.starts_with?("refs/tags/")
        next if ref.peeled?
        repo.write_ref(ref.name, ref.oid)
      end
    end

    # Establishes the local default branch and HEAD after a clone, then checks
    # the branch out. Falls back to a detached HEAD if the default branch can
    # not be determined.
    private def finalize_head(repo : Repository, advertisement : Advertisement) : Nil
      target = advertisement.head_target || guess_default_branch(advertisement)

      if target && (ref = advertisement.reference(target))
        repo.write_ref(target, ref.oid)
        repo.attach_head(target)
        repo.checkout(ref.oid)
      elsif oid = advertisement.head_oid
        repo.detach_head(oid)
        repo.checkout(oid)
      else
        raise ProtocolError.new("server advertised refs but no resolvable HEAD")
      end
    end

    # Picks a sensible default branch when the server did not advertise a HEAD
    # symref: prefer main, then master, else the first branch.
    private def guess_default_branch(advertisement : Advertisement) : String?
      branches = advertisement.references.select(&.branch?).reject(&.peeled?)
      ["refs/heads/main", "refs/heads/master"].each do |candidate|
        return candidate if branches.any? { |ref| ref.name == candidate }
      end
      branches.first?.try(&.name)
    end

    private def default_branch_name(advertisement : Advertisement) : String?
      (advertisement.head_target || guess_default_branch(advertisement))
        .try(&.lchop("refs/heads/"))
    end

    # Handles cloning an empty remote: just lay down an empty repo skeleton.
    private def empty_clone(dir : String, advertisement : Advertisement) : Repository
      Repository.init(dir).tap do |repo|
        repo.write_config(@remote_name, @url.to_s)
      end
    end
  end
end
