# Contributing to crux

How to set up a dev environment, find your way around, and get changes merged.

## Development setup

### Prerequisites

- **[Crystal](https://crystal-lang.org)**
- **[Task](https://taskfile.dev)**: task runner of choice
- **[Commitizen](https://commitizen-tools.github.io/commitizen/)** (`cz`): enforces conventional commit structure
- **[pre-commit](https://pre-commit.com)**: git hooks manager
- **[Ameba](https://github.com/crystal-ameba/ameba)**: crystal linter, included as a development dependency

### Getting started

```sh
git clone https://github.com/<you>/crux.git
cd crux
shards install
pre-commit install --hook-type commit-msg   # commitizen runs at commit-msg stage
task spec
```

## Architecture

Crux is a hierarchical Cling CLI. A root command dispatches to namespace commands, which dispatch to implementation commands. 

For an illustrated representative example, Kubernetes domain logic lives under the `src/kube/` namespace so commands stay thin: 

```
src/
├── main.cr                     # Entry point
├── crux.cr                     # Root command + build metadata
├── commands/
│   ├── base.cr                 # Help templates, logging, error handling
│   ├── global.cr               # Global options (eg --help, --debug)
│   ├── version.cr              # `crux version`
│   ├── kube.cr                 # `kube` namespace
│   └── kube/
│       ├── ysplit.cr           # `kube ysplit`
│       └── helmsplit.cr        # `kube helmsplit`
└── kube/                       # Shared Kubernetes domain logic (no CLI concerns here)
    ├── k8s_doc.cr              # Single Kubernetes object model
    ├── manifest_splitter.cr    # Multi-doc manifest splitting
    └── yaml_block.cr           # YAML block-scalar rendering
```

## Tests

Specs mirror the source layout under `spec/`. External HTTP is mocked with [webmock](https://github.com/manastech/webmock.cr) so you don't hit any real external resources.

```sh
task spec                                       # full suite
crystal spec spec/commands/kube/ysplit_spec.cr  # single file
```

Tests for any new features should cover the expected case, an edge case, and a failure case. Tests for any bugs should cover the current behavior failure to prevent regressions and confirm the fix.

You can generate a local coverage report with `task coverage`, but don't worry too much about it since test coverage is validated against PRs.

## Style

- Format with `crystal tool format` before committing.
- Keep `task lint` (Ameba) clean.
- Document any public functions, but keep it succinct for god's sake. We're not all robots.
- Comments explain _why_, not _what_. Unless it's a super dense change or needs extra justification.

## Submitting changes

1. Branch off `main`, make your change with tests.
2. Run `task` (specs + lint) until green.
3. Commit with `cz commit` or the `commit-msg` hook is gonna get ya. Just follow the prompt.
4. Push and open a PR describing the change and its motivation. 
    - We squash commit in this house, so the PR title must follow the same conventional-commit structure.

## Questions?

Open an issue.
