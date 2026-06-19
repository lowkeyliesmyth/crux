# Git over SSH, implemented in pure Crystal.
#
# This module speaks git's smart transfer protocol (pkt-line framing, ref
# advertisement, want/have negotiation, side-band multiplexing and packfile
# decoding) directly, using the system `ssh` client only as the transport --
# exactly how git's own `ssh://` remotes work. No git binary is invoked.
#
# It is intentionally self-contained and free of any dependency on the rest of
# the `crux` application, so it can be lifted out into a standalone shard. The
# public entry point is `Git::Client`:
#
# ```
# require "./git"
#
# # Clone a repository over SSH.
# repo = Git::Client.clone("git@github.com:owner/repo.git", "repo")
#
# # Later, fetch and fast-forward.
# client = Git::Client.for("git@github.com:owner/repo.git")
# client.pull(repo)
# ```
#
# Scope: the read path (clone, fetch, pull) is implemented. The write path
# (push / receive-pack and pack generation) is a planned addition and will
# slot in alongside the existing transport and protocol layers.
require "./git/errors"
require "./git/object"
require "./git/delta"
require "./git/pack"
require "./git/pkt_line"
require "./git/url"
require "./git/capabilities"
require "./git/reference"
require "./git/advertisement"
require "./git/transport"
require "./git/protocol"
require "./git/tree"
require "./git/object_store"
require "./git/checkout"
require "./git/repository"
require "./git/client"

module Git
  # The version of this git module, independent of the host application.
  MODULE_VERSION = "0.1.0"
end
