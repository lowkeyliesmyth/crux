# crux

A small single binary Crystal CLI for everyday DevEx and operations workflows. 

Crux is an **opinionated but transparent** single-binary CLI that consolidates utilities used in the day-to-day. It favors convention over configuration, and tells you exactly what it is doing whenever it touches your system.

See `AGENTS.md` for the architecture and conventions for adding new commands.

## Installation

Homebrew:

```sh
brew install lowkeyliesmyth/tap/crux
```

Or grab a binary for your platform from the [releases page](https://github.com/lowkeyliesmyth/crux/releases).

## Quick start

Crux groups commands by namespace. The `kube` namespace handles (currently only) Kubernetes manifest wrangling.

**Split a multi-doc manifest into one file per object:**

```sh
# from a local mega-manifest
crux kube ysplit ./out -f manifest.yaml

# from a remote URL
crux kube ysplit ./out -r https://example.com/manifests.yaml
```

**Render a Helm chart and split its output into one file per object:**

```sh
# remote chart targeting a specific version
crux kube helmsplit ./out jetstack/cert-manager -v 1.20

# local chart with a few values.yaml files and a project name  prefixed to every output file
crux kube helmsplit ./out ./charts/myapp -f base.yaml -f prod.yaml -p myapp
```

**Generate per-cluster ConfigMap patches from the rendered output:**

For use with the rendered manifests pattern and generating kustomize-applied override patches.

```sh
crux kube helmsplit ./out sysdig/shield -o overrides.kyaml
```

where `overrides.kyaml` declares the clusters, an output path template, the keys to patch, and the content to patch them with:

```yaml
---
{
  clusters: ["dev", "prod"],
  output: "clusters/${cluster}/patches/override-${object}.yaml",
  overrides: [{
    configmap: "shield-cluster",
    patches: [{
      outerPath: "data[cluster-shield.yaml]",
      innerPath: "cluster_config.name",
      valueFrom: "cluster.name",
    }],
  }],
}
```

Every crux run writes a `_PROVENANCE.md` file recording the exact command siganture adjacent to the output files, giving you and your team the best chance to reproduce results.

**Getting help.** `--help` works at every command and namespace level:

```sh
crux --help
crux kube --help
crux kube helmsplit --help
```

## Development

```bash
# Run spec tests
task spec

# Run ameba linter
task lint

# Build the crux binary
task build

# Format code
crystal tool format

# Run a specific test file
crystal spec spec/any_spec.cr
```

## Contributing

Issues and PRs welcome. Please include test coverage and run `crystal spec` before opening a PR.

## Contributors

- [lowkey](https://github.com/lowkeyliesmyth) — creator and maintainer
