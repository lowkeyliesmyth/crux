module Git
  # A single advertised reference: a name (e.g. `refs/heads/main`) bound to an
  # object id. Peeled tag entries (`refs/tags/v1^{}`) are represented with
  # their `^{}` suffix intact so callers can distinguish them.
  struct Reference
    getter name : String
    getter oid : String

    def initialize(@name : String, @oid : String)
    end

    # True for the peeled-tag pseudo-ref `<tag>^{}`.
    def peeled? : Bool
      @name.ends_with?("^{}")
    end

    # True for a branch under `refs/heads/`.
    def branch? : Bool
      @name.starts_with?("refs/heads/")
    end

    # The short branch name, or nil if this is not a branch ref.
    def branch_name : String?
      branch? ? @name.lchop("refs/heads/") : nil
    end
  end
end
