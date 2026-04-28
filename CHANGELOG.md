## 0.3.3 (2026-04-27)

### Feat

- **ysplit,helmsplit**: store command source provenance in rendered output (#11)

### Build System

- **GHA-release**: update release workflow to explicitly target openssl3 (#10)

### CI

- **release**: link up ci so crux releases trigger homebrew releases too

## 0.3.3-a0 (2026-04-24)

### Build System

- **GHA-release**: update release workflow to explicitly target openssl3

## 0.3.2 (2026-04-24)

### CI

- **GHA-release**: forcing a change to release new artifacts

## 0.3.1 (2026-04-23)

### Docs

- **readme**: publish an actual readme

### CI

- **GHA**: fix release action git attribution, enable shame releases (#9)

## 0.3.0 (2026-04-24)

### Feat

- **helmsplit**: implement helm chart to yaml file splitting command (#4)

### CI

- **cz**: jump through hoops to get all valid change types in the changelog (#8)
- **GHA**: refactor ci to ssh tag signing, enable release dry-runs, refactor changelog (#7)
- **GHA**: fix release workflow to support prerelease and official release versions (#6)
- **GHA**: automate spec tests, ameba linting, and release builds (#5)

## 0.2.0 (2026-04-22)

### Feat

- **ysplit**: implement local and remote kube yaml splitting functionality (#2)
- **version**: implement version command
