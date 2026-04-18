# Base Command Infrastructure

Shared functionality and behaviors inherited by all crux commands.

- [ ] Refactor help_template method to more closely mirror Cling::Formatter.generate structure
  - Current implementation only partially implements Cling::Formatter
  - Review upstream for missing functionality
- [ ] Improve logging helper methods (debug, info, warn, error)
  - Look to charmbracelet/log for inspiration on expanding helper functionality
  - Consider adding enhanced visualizations
