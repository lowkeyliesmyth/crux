# Crux CLI - Project Planning

## Project Overview

**Crux** is a modular CLI tool built in Crystal that provides Kubernetes-focused utilities and development environment management. The project begins with YAML splitting functionality and will expand to include dependency management and environment setup capabilities.

## Scope & Objectives

### Phase 1: Core YAML Processing (MVP)
- Port Python `ysplit` functionality to Crystal under `crux kube ysplit`
- Support both local files and remote URLs for YAML processing
- Decompose concatenated Kubernetes YAML manifests into separate files
- Maintain compatibility with existing `ysplit` command-line interface

### Phase 2: Extensibility Foundation
- Establish modular command structure using namespaced subcommands
- Implement plugin-ready architecture for future expansion
- Create comprehensive testing framework for CLI operations

### Phase 3: Environment Management
- Add `crux up` command for dependency detection and installation
- Integration with mise and Homebrew for tool management
- Support for AWS CLI, kubectl, and other common DevOps tools

## Technology Stack

### Core Language & Framework
- **Crystal 1.16+**: Primary development language for performance and Ruby-like syntax
- **Cling**: CLI framework for modular command structure and argument parsing
- **Crystal Spec**: Built-in testing framework for comprehensive test coverage

### Key Dependencies
- **YAML**: Crystal's built-in YAML library for Kubernetes manifest processing
- **HTTP::Client**: Standard library for remote file fetching
- **File utilities**: Standard library for file operations and path management

### Development Tools
- **Crystal formatter**: Code formatting and style consistency
- **Shards**: Dependency management via `shard.yml`
- **GitHub Actions**: CI/CD pipeline for testing and multi-platform builds

## Architecture Design

### Command Structure
```
crux
├── kube
│   ├── ysplit          # YAML splitting functionality
│   └── [future k8s commands]
├── up                  # Dependency management
└── [future namespaces]
```

### Modular Organization
- `src/crux`: Main application entry point
- `src/commands/`: Command implementations organized by namespace
- `src/commands/kube/`: Kubernetes-related commands
- `src/utils/`: Shared utilities (YAML processing, HTTP, file operations)
- `spec/`: Comprehensive test suite mirroring source structure

### Core Components
1. **Command Router**: Central dispatch for namespace routing
2. **YAML Processor**: Core functionality for parsing and splitting YAML documents
3. **HTTP Fetcher**: Remote URL handling with error management
4. **File Manager**: Local file operations and output directory management
5. **Dependency Checker**: Future component for tool detection and installation

## Development Approach

### Development Philosophy
- **Modular by Design**: Each command namespace is self-contained and testable
- **Type Safety**: Leverage Crystal's type system for robust error handling
- **Performance First**: Utilize Crystal's compilation benefits for fast execution
- **Ruby Familiarity**: Maintain Ruby-like patterns where possible for developer comfort

### Testing Strategy
- **Unit Tests**: Individual component testing with Crystal Spec
- **Integration Tests**: End-to-end command execution testing
- **CLI Testing**: Argument parsing and output validation
- **Error Handling**: Comprehensive edge case and error condition testing

### Code Quality Standards
- Crystal's built-in formatter for consistent code style
- Type annotations where clarity improves (optional but encouraged)
- Comprehensive documentation for public APIs
- Error messages that guide users toward solutions

## Build & Distribution

### Local Development
- Simple `crystal build` for development iterations
- `shards install` for dependency management
- Local testing with `crystal spec`

### Production Builds
- Optimized compilation with `--release` flag
- Static linking via Alpine Linux containers
- Multi-platform builds: macOS (x86_64, ARM64), Linux (x86_64, ARM64)

### Distribution Channels
1. **GitHub Releases**: Primary distribution with automated binary builds
2. **Package Managers**: Future Homebrew formula for macOS users
3. **Container Images**: Docker images for containerized environments

## Timeline & Milestones

### Milestone 1: Project Foundation (Week 1-2)
- Project structure setup with Crystal and Cling
- Basic command routing and argument parsing
- CI/CD pipeline establishment
- Development environment documentation

### Milestone 2: YAML Splitting Core (Week 3-4)
- Core YAML processing functionality
- Local file handling and output generation
- Remote URL fetching capability
- Comprehensive test coverage

### Milestone 3: Feature Parity (Week 5-6)
- Complete `ysplit` functionality port
- Error handling and edge cases
- Documentation and usage examples
- Performance optimization

### Milestone 4: Foundation for Growth (Week 7-8)
- Modular architecture validation
- Plugin system design
- Preparation for `crux up` command development
- Release preparation and distribution setup

## Risk Assessment & Mitigation

### Technical Risks
- **Crystal Learning Curve**: Mitigated by comprehensive documentation and Ruby similarity
- **Cling Framework Maturity**: Low risk due to active maintenance and community usage
- **Multi-platform Builds**: Addressed through Docker-based build environments

### Project Risks
- **Scope Creep**: Controlled through phased approach and clear milestone definitions
- **Performance Requirements**: Crystal's native compilation provides strong foundation
- **Maintenance Overhead**: Modular design enables focused development and testing

## Success Criteria

### Phase 1 Success Metrics
- Complete functional parity with Python `ysplit` tool
- Sub-second execution time for typical YAML files (< 10MB)
- Zero-dependency binary distribution
- Comprehensive test coverage (>90%)

### Long-term Success Indicators
- Smooth addition of new command namespaces
- Community adoption and contribution
- Performance improvements over equivalent tools
- Reliable multi-platform distribution

## Future Considerations

### Extensibility Plans
- Plugin architecture for third-party extensions
- Configuration file support for user preferences
- Integration with other Kubernetes tooling
- API for programmatic usage

### Community & Maintenance
- Open source contribution guidelines
- Semantic versioning for stable API evolution
- Regular dependency updates and security patches
- Community feedback integration for feature prioritization

This planning document serves as the foundational roadmap for Crux development, ensuring a methodical approach to building a robust, extensible CLI tool that serves both immediate YAML processing needs and future development environment management requirements.
