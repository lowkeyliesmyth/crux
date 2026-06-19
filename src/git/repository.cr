require "./errors"
require "./object"
require "./object_store"
require "./tree"
require "./checkout"

module Git
  # A local git repository on disk: the `.git` directory layout, its refs and
  # HEAD, the object store, and working-tree checkout. This is deliberately
  # minimal -- just what clone/fetch/pull need -- and writes only the loose,
  # human-readable forms of refs and config.
  class Repository
    GIT_DIR_NAME = ".git"

    getter work_dir : String
    getter git_dir : String
    getter store : ObjectStore

    def initialize(@work_dir : String, @git_dir : String)
      @store = ObjectStore.new(File.join(@git_dir, "objects"))
    end

    # Opens (without creating) the repository whose working tree is `work_dir`.
    def self.open(work_dir : String) : Repository
      new(work_dir, File.join(work_dir, GIT_DIR_NAME))
    end

    # Creates a fresh repository skeleton under `work_dir`/.git. Raises if one
    # already exists there.
    def self.init(work_dir : String) : Repository
      repo = open(work_dir)
      if Dir.exists?(repo.git_dir)
        raise Error.new("a git directory already exists at #{repo.git_dir}")
      end
      repo.create_layout
      repo
    end

    # Builds the minimal directory tree and default files for a new repo.
    protected def create_layout : Nil
      Dir.mkdir_p(File.join(@git_dir, "objects"))
      Dir.mkdir_p(File.join(@git_dir, "refs", "heads"))
      Dir.mkdir_p(File.join(@git_dir, "refs", "tags"))
      Dir.mkdir_p(File.join(@git_dir, "refs", "remotes"))
      attach_head("refs/heads/main")
      write_default_config
    end

    # Writes (or overwrites) a ref such as "refs/heads/main" with `oid`.
    def write_ref(name : String, oid : String) : Nil
      path = ref_path(name)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, "#{oid}\n")
    end

    # Deletes a ref if it exists. No-op otherwise.
    def delete_ref(name : String) : Nil
      path = ref_path(name)
      File.delete(path) if File.exists?(path)
    end

    # Reads a ref's object id, or nil if the ref does not exist.
    def read_ref(name : String) : String?
      path = ref_path(name)
      return nil unless File.exists?(path)
      File.read(path).strip
    end

    # Points HEAD at a ref (a symbolic ref).
    def attach_head(target : String) : Nil
      File.write(File.join(@git_dir, "HEAD"), "ref: #{target}\n")
    end

    # Points HEAD directly at an object id (detached HEAD).
    def detach_head(oid : String) : Nil
      File.write(File.join(@git_dir, "HEAD"), "#{oid}\n")
    end

    # The ref HEAD symbolically points at (e.g. "refs/heads/main"), or nil if
    # HEAD is detached.
    def head_target : String?
      path = File.join(@git_dir, "HEAD")
      return nil unless File.exists?(path)
      content = File.read(path).strip
      content.starts_with?("ref: ") ? content.lchop("ref: ").strip : nil
    end

    # Explodes resolved pack objects into the loose object store.
    def store_objects(objects : Enumerable(Object)) : Int32
      @store.write_all(objects)
    end

    # Checks out the tree of `commit_oid` into the working directory.
    def checkout(commit_oid : String) : Nil
      object = @store.read(commit_oid)
      raise ObjectError.new("missing commit object #{commit_oid}") unless object
      commit =
        case object.type
        when .commit? then Commit.parse(object.data)
        when .tag?    then resolve_tag_to_commit(object)
        else
          raise ObjectError.new("cannot checkout a #{object.type} object")
        end
      Checkout.new(@store).materialize(commit.tree, @work_dir)
    end

    # Determines whether `ancestor` is reachable from `descendant` by walking
    # the commit graph. Used to gate fast-forward updates.
    def ancestor?(ancestor : String, descendant : String) : Bool
      return true if ancestor == descendant
      seen = Set(String).new
      queue = [descendant]
      until queue.empty?
        oid = queue.shift
        next unless seen.add?(oid)
        object = @store.read(oid)
        next unless object && object.type.commit?
        commit = Commit.parse(object.data)
        return true if commit.parents.includes?(ancestor)
        queue.concat(commit.parents)
      end
      false
    end

    # Writes a `[remote "<name>"]` section pointing at `url`, in addition to
    # the core section, replacing any existing config.
    def write_config(remote_name : String, url : String, default_branch : String? = nil) : Nil
      io = IO::Memory.new
      io << "[core]\n"
      io << "\trepositoryformatversion = 0\n"
      io << "\tfilemode = true\n"
      io << "\tbare = false\n"
      io << "[remote \"" << remote_name << "\"]\n"
      io << "\turl = " << url << '\n'
      io << "\tfetch = +refs/heads/*:refs/remotes/" << remote_name << "/*\n"
      if branch = default_branch
        io << "[branch \"" << branch << "\"]\n"
        io << "\tremote = " << remote_name << '\n'
        io << "\tmerge = refs/heads/" << branch << '\n'
      end
      File.write(File.join(@git_dir, "config"), io.to_s)
    end

    private def write_default_config : Nil
      io = IO::Memory.new
      io << "[core]\n"
      io << "\trepositoryformatversion = 0\n"
      io << "\tfilemode = true\n"
      io << "\tbare = false\n"
      File.write(File.join(@git_dir, "config"), io.to_s)
    end

    private def resolve_tag_to_commit(tag : Object) : Commit
      # An annotated tag's first "object" header names what it points at; follow
      # the chain until a commit is reached.
      current = tag
      10.times do
        oid = nil
        String.new(current.data).each_line do |line|
          break if line.empty?
          oid = line.lchop("object ").strip if line.starts_with?("object ")
        end
        raise ObjectError.new("annotated tag missing object header") unless oid
        target = @store.read(oid)
        raise ObjectError.new("missing tag target #{oid}") unless target
        return Commit.parse(target.data) if target.type.commit?
        current = target
      end
      raise ObjectError.new("tag chain too deep")
    end

    private def ref_path(name : String) : String
      File.join(@git_dir, name)
    end
  end
end
