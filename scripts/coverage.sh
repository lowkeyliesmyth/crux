#!/usr/bin/env bash
# Generate a local code coverage report using kcov.
# Output: ./coverage/index.html  (open in a browser)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo 'require "./spec/**"' > ./all_specs.cr
mkdir -p ./bin
crystal build ./all_specs.cr -o ./bin/all_specs

kcov --clean --include-path="./src" ./coverage ./bin/all_specs --order=random

crystal tool unreachable --format=codecov ./all_specs.cr \
  > ./coverage/unreachable.codecov.json

echo
echo "kcov report:        ./coverage/index.html"
echo "unreachable report: ./coverage/unreachable.codecov.json"
