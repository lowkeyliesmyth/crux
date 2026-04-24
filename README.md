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

## Usage

```sh
crux --help
crux kube
crux kube helmsplit
```

Every command accepts `--help`, `--debug`, and `--no-color`.

## Development

Requires Crystal >= 1.16.3.

```sh
shards install
crystal spec
crystal build src/main.cr -o crux
```

## Contributing

Issues and PRs welcome. Please include test coverage and run `crystal spec` before opening a PR.

## Contributors

- [lowkey](https://github.com/lowkeyliesmyth) — creator and maintainer
