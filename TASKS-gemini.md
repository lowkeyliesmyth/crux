# Initial Project Tasks: crux CLI

This document outlines the initial tasks required to get the `crux` CLI project started.

## Phase 1: Project Setup & Foundation

* [ ] **1.1: Initialize Crystal Project:**
    * Use the Crystal CLI to create a new application project: `crystal init app crux`.

* [ ] **1.2: Add Dependencies to `shard.yml`:**
    * Add the `cling` shard to the `shard.yml` file.
        ```yaml
        dependencies:
          cling:
            github: devnote-dev/cling
            version: ~> 3.0.0
        ```
    * Run `shards install` to fetch and install the dependencies.

* [ ] **1.3: Create Initial Directory Structure:**
    * Create the necessary directories for the command structure as outlined in `PLANNING.md`.
        * `src/crux/commands/`
        * `src/crux/commands/kube/`

## Phase 2: `crux kube ysplit` Implementation

* [ ] **2.1: Set up `cling` CLI structure in `src/cli.cr`:**
    * Define the `crux` root command, the `kube` subcommand, and the `ysplit` subcommand.
    * Add the required arguments and options to the `ysplit` command: `--file`, `--remote`, `--output`, `--name`.

* [ ] **2.2: Implement core logic in `src/crux/commands/kube/ysplit.cr`:**
    * Create a `Ysplit` class or module to encapsulate the functionality.
    * Implement methods for reading from a local file and fetching from a remote URL.
    * Implement the main processing method that uses `YAML.parse_all`.

* [ ] **2.3: Implement File Writing and Error Handling:**
    * In the file writing logic, implement the strategy for handling filename collisions by checking for existing files and appending a counter (`-1`, `-2`, etc.) if necessary.
    * When processing documents, add checks for the presence and validity of `metadata.name` and `kind`. If a document is invalid, print a colorized warning to `STDERR` (e.g., using `Colorize.yellow`) and skip to the next document.

* [ ] **2.4: Connect `cling` to the core logic:**
    * In the `run` method of the `ysplit` command in `src/cli.cr`, call the methods from the `Ysplit` module/class to execute the splitting logic.
    * Use `Colorize` to provide simple, colored feedback to the user (e.g., "Successfully wrote 5 files.").

## Phase 3: Testing & Refinement

* [ ] **3.1: Write Unit Tests:**
    * In the `spec/` directory, create a new spec file for the `ysplit` command.
    * Write tests for the core logic:
        * Test successful parsing of a multi-document YAML string.
        * Test the filename generation logic.
        * **Test the filename collision logic specifically.**
        * **Test the skipping of invalid documents.**
        * Test reading from a (mocked) local file and a (mocked) remote URL.

* [ ] **3.2: Manual Testing:**
    * Compile the application: `crystal build src/crux.cr`.
    * Run the compiled binary with various inputs to ensure it behaves as expected, including cases that should trigger warnings and filename collisions.

* [ ] **3.3: Refine General Error Handling:**
    * Add `begin...rescue` blocks to handle potential exceptions (e.g., `File::NotFoundError`, `HTTP::Error`, `YAML::ParseException`).
    * Provide user-friendly, colorized error messages for fatal errors.

## Phase 4: Documentation

* [ ] **4.1: Update `README.md`:**
    * Add a description of the `crux` CLI and its purpose.
    * Provide installation instructions.
    * Document the usage of the `crux kube ysplit` command with examples, including the different flags.

* [ ] **4.2: Add Code Comments:**
    * Add comments to the Crystal code to explain the logic, especially for the error handling and filename collision sections.


