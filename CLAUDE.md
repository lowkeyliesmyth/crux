### 🔄 Project Awareness & Context
- Always read PLANNING.md at the start of a new conversation to understand the project's architecture, goals, style, and constraints.
- Check TASKS.md before writing or generating any code. starting a new task.
	-  If the work item isn’t listed, create a new entry under “Discovered During Work” for accurate tracking.
- Follow structure, naming conventions, and architecture patterns described in PLANNING.md.

### 🧱 Code Structure & Modularity
- No file should exceed 500 logical lines of code.
	- If a file approaches this limit, refactor well-scoped modules, grouped by responsibility.
- Organize code into clearly separated modules, grouped by feature or responsibility.
- Use clear, consistent imports (prefer relative imports within packages).
- Avoid cyclical dependencies or deep nested structures—promote shallow and maintainable architecture.

### 🧪 Testing & Reliability
- Always create unit tests for new features (functions, classes, routes, etc).
- After updating any logic, check whether existing unit tests need to be updated. If so, do it.
- Tests MUST reflect actual usage scenarios, not just implementation checks.
- Minimum test coverage per unit:
  - One test for expected use
  - One edge case
  - One failure/error condition
- Tests SHOULD be colocated with application code or placed in a mirrored folder structure (e.g., /tests).
- Always "mock" calls to external services like DBs so you are not directly interacting with anything "for real"

### ✅ Task Completion
- Mark completed tasks in TASKS.md immediately after finishing them.
- Add new sub-tasks or TODOs discovered during development to TASKS.md under a “Discovered During Work” section.

### 📎 Style & Consistency
- Use consistent naming conventions across all files, classes, variables, and artifacts.
- Code style (indentation, line length, spacing, etc.) MUST follow project-specific formatter or style guide.
- Comments SHOULD explain “why” a piece of code exists, not just “what” it does.
- Every public-facing function or class MUST contain a summary docstring or explanatory comment block with:
  - Input parameters (names + types)
  - Return value or side effect
  - Exceptions raised or edge conditions
- Follow framework-specific configuration and dependency management practices (e.g., package management, build tools).

### 📚 Documentation & Explainability
- README.md MUST be updated when new features are added, dependencies change, or setup steps are modified.
- Core workflows (scripts, config bootstraps, build instructions) MUST be documented for others to reproduce.
- Use inline comments for non-obvious logic, decisions, or workarounds.
- Prefer “Reason:” comments to justify architectural complexity or deviations from framework defaults.
- For UIs, add usage documentation or examples if not self-documenting.

### 🧠 AI Behavior Rules
- NEVER assume missing context. Ask questions if uncertain
- NEVER hallucinate libraries or functions – only use known, verified language-appropriate packages and libraries
- ALWAYS confirm file paths and module names exist before referencing them in code or tests.
- NEVER delete or overwrite existing code unless explicitly instructed to or if part of a task from TASKS.md.
