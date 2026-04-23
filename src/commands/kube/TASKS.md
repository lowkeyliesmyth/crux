# Namespace: kube

Kubernetes-related utilities for manifest manipulation and resource management.

## Subcommand: ysplit

Splits multi-document YAML manifests into separate files (one per K8s object).

### Future features to Implement

- [ ] Allow outdir to be optional, default to CWD
- [ ] Add support for cleaning out target directory of existing files
  - Ensure that we add a prompt for confirmation by the user before executing
- [ ] Add support for a --force option dependent on the --clean option, to override confirmation prompt
  - Useful when crux is run in CI or other automation
  - Either fail or silently ignore the command if not also paired with the 'clean' command
- [ ] Sanitize user input for prefix option
- [ ] Validate that user provided outdir arg is a valid filesystem path

### Bugs to Fix

- [ ] Fix option inheritance issue: help, debug, and no-color options not being inherited from Base.pre_run method
  - Likely some inheritance problem with registering the ysplit grandchild command in the child kube.cr instead of parent crux.cr

## Subcommand: helmsplit

Renders a Helm chart and splits the  resulting multi-doc output into separate files (one per K8s  object).

### Future features to implement
- [ ] validate user-submitted chart repo string against repositories.yaml repos list
- [ ] Make the external helm call testable through an abstract collaborator refactor to helmsplit and helmsplit_spec

### Bugs to fix
