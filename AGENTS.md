# crux - Developer Experience CLI

## Project Overview

Crux is a Crystal-based command-line tool designed to streamline day-to-day developer workflows. The CLI provides a collection of utilities organized into namespaced command groups, currently focused on Kubernetes manifest manipulation and other developer tasks.

## Design Principles

- Simple, focused commands doing one thing well
- Consistent colorized output across all commands
- Progressive disclosure (help at every level)
- Fail fast with clear error messages
- Debug mode for troubleshooting (`--debug`)

## Architecture

### Command Structure

Crux follows a hierarchical command architecture with three levels:

1. **Root Command** (`crux`) - Entry point defined in `src/crux.cr`
2. **Namespace Commands** (e.g., `kube`) - Organizational containers for related functionality
3. **Implementation Commands** (e.g., `ysplit`) - Actual feature implementations

**Example:** `crux kube ysplit <outdir> -f manifest.yaml`

### File Organization

```
src/
├── main.cr                    # Application entry point
├── crux.cr                    # Root command definition
├── commands/
│   ├── base.cr               # Base command class with shared behaviors
│   ├── version.cr            # Version display command
│   ├── kube.cr               # Kubernetes namespace command
│   └── kube/
│       └── ysplit.cr         # YAML splitting implementation
spec/
└── commands/
    └── kube/
        └── ysplit_spec.cr    # Tests mirror source structure
```

### Key Components

**Base Command Class** (`src/commands/base.cr`)
- Extends `Cling::Command` with custom formatting and behaviors
- Provides global options: `--help`, `--debug`, `--no-color`
- Implements custom help templates with colorized output
- Defines logging methods: `debug()`, `info()`, `warn()`, `error()`
- Handles error formatting and stack traces

**Command Registration**
- Namespace commands register their subcommands in `setup()` method
- Parent commands display help when called without subcommands
- Inheritance chain: Implementation < Namespace < Base < Cling::Command

## Technology Stack

- **Language:** Crystal >= 1.16.3
- **CLI Framework:** Cling >= 3.1.0 (argument parsing, command routing)
- **Linting:** Ameba ~> 1.6.4
- **Testing:** Crystal spec framework

## Code Style

- Maximum file size: 500 logical lines of code
- Colorized terminal output using `colorize` shard
- Error handling through custom exception classes

## Development Workflow

### Task Management

Each namespace command maintains a dedicated `TASKS.md` file organized by subcommand:

```
TASKS.md structure:
# Namespace: kube

## Subcommand: ysplit
- [ ] Task description
- [x] Completed task

## Subcommand: another-command
- [ ] Task description
```

**Location:** Tasks live alongside their namespace command file (e.g., `src/commands/TASKS.md` for `kube`)

**Purpose:** Track planned features, improvements, and migrate TODO comments from code

### Testing

- Tests use Crystal's built-in spec framework
- Test files mirror source structure in `spec/` directory
- Run tests: `crystal spec`

### Building

- Build target: `crux` (defined in shard.yml)
- Compile: `crystal build src/main.cr`
- Build metadata injected at compile time: `VERSION`, `BUILD_DATE`, `BUILD_HASH`

## Implementation Patterns

### Adding New Commands

1. **Namespace Command** (if new category):
   - Create `src/commands/namespace.cr`
   - Extend `Base` class
   - Register in `src/crux.cr`
   - Create `src/commands/TASKS.md`

2. **Implementation Command**:
   - Create `src/commands/namespace/feature.cr`
   - Extend namespace class (e.g., `Kube`)
   - Define arguments and options in `setup()`
   - Implement logic in `run()`
   - Add test at `spec/commands/namespace/feature_spec.cr`
   - Document in namespace TASKS.md

### Error Handling

Commands should define custom exception classes inheriting from a base domain exception:

```crystal
class YSplitError < Exception
end

class YAMLValidationError < YSplitError
end
```

Handle exceptions in `run()` with rescue blocks and use Base logging methods.

### Option Validation

Use `pre_run()` for mutual exclusivity checks, required option validation, and argument sanitization.

## Build Metadata

Build information is embedded at compile time:
- `Crux::VERSION` - from shard.yml
- `Crux::BUILD_DATE` - ISO date of build
- `Crux::BUILD_HASH` - Short git commit hash
