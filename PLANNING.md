# Project: crux CLI
Generated with input from gemini-2.5-pro

## 1. Project Overview

`crux` is a command-line interface (CLI) tool written in the Crystal programming language. It will provide a collection of helpful, modular, and extensible commands and utilities for developers. The initial focus of the project is to provide functionality related to Kubernetes manifest management.

## 2. Scope

The initial scope of the project is to create the `crux` CLI with a single subcommand: `kube ysplit`.

### 2.1. `crux kube ysplit`

This subcommand will be a port of the provided `ysplit.py` script. Its core functionality will be to take a single, multi-document YAML file and split it into multiple individual YAML files.

**Features:**

* Read a multi-document YAML file from a local file path.
* Read a multi-document YAML file from a remote URL.
* Parse the YAML stream into individual documents.
* For each YAML document, generate a new file named according to the pattern: `<project-name>-<metadata.name>-<kind>.yaml`.
* Write each YAML document to its corresponding new file in a specified output directory.
* Provide clear and helpful command-line options and help text.
* Use simple colorization for user feedback (e.g., green for success, yellow for warnings, red for errors).

## 3. Technology Stack

* **Language:** Crystal
* **CLI Framework:** [devnote-dev/cling](https://github.com/devnote-dev/cling)
* **Dependency Management:** Crystal Shards
* **YAML Parsing:** Crystal's built-in `YAML` module.
* **HTTP Client:** Crystal's built-in `HTTP::Client` for fetching remote files.
* **Colorization:** Crystal's built-in `Colorize` module.

## 4. High-Level Direction

### 4.1. Project Structure

The project will follow a standard, modular Crystal application structure to accommodate future growth.



crux/
├── spec/
│ ├── spec_helper.cr
│ └── ... (unit tests)
├── src/
│ ├── commands/
│ │ ├── kube/
│ │ │ └── ysplit.cr
│ │ ├── kube.cr
│ │ └── up.cr
│ └── version.cr
│ ├── main.cr (main application file)
│ └── crux.cr (cling command setup)
├── README.md
└── shard.yml

### 4.2. CLI Command Structure

The CLI will be structured with nested commands using `cling` to ensure extensibility.

* `crux` - The root command.
* `crux kube` - A namespace for Kubernetes-related commands.
* `crux kube ysplit` - The command to split YAML files.
* `crux up` - (Future) A command to manage development environment dependencies.

### 4.3. Code Implementation & Error Handling

* **`src/crux.cr`**: This file will define the command structure, arguments, and options using `cling`. It will be the main entry point for the CLI logic.
* **`src/crux/commands/kube/ysplit.cr`**: This file will contain the core logic for the `ysplit` command.
* **YAML Parsing Errors:** If a document within the YAML stream is invalid or missing required fields (`metadata.name`, `kind`), the tool will print a colorized warning to `STDERR`, skip that document, and continue processing the rest.
* **Filename Collisions:** If a file with the target name already exists, the tool will append a hyphen and a counter to the new filename (e.g., `my-app-deployment-1.yaml`, `my-app-deployment-2.yaml`).
* **General Errors:** The application will handle other potential errors gracefully (e.g., file not found, invalid URL) and provide informative, colorized messages to the user.

## 5. Future Considerations

* **New Commands:**
    * Implement the `crux up` command to detect and install required developer tools (like `aws-cli`) using a package manager like `mise` or `homebrew`.
    * Add more subcommands under the `kube` namespace (e.g., `kustomize`, `lint`).
    * Introduce other top-level command namespaces (e.g., `crux git`, `crux docker`).
* **Developer Experience (DX) Improvements:**
    * Implement more robust logging.
    * Add shell completion support.
    * Investigate more advanced TUI/CLI libraries for features like progress bars (`progress.cr` shard) or interactive interfaces, similar to Go's Bubble Tea library (`Keimeno` shard).
