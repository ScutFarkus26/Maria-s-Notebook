# Repository Organization Plan

This log governs the incremental repository reorganization. The work is intentionally split into small, independently reversible commits. File moves must not include type renames, formatting sweeps, or behavior changes.

## Validation rules

Every organization commit must:

1. Cover one coherent area.
2. Update affected documentation and path references in the same commit.
3. Pass `git diff --cached --check`.
4. Preserve the macOS and iOS build baselines.
5. Run relevant tests, with the full suite at phase boundaries.
6. Record validation results, exceptions, and the commit below.

Build commands use Xcode 27 beta at `/Applications/Xcode-beta.app/Contents/Developer` without changing the machine-wide `xcode-select` setting.

## Execution log

### Preflight checkpoint

- Status: Complete
- Commit: `b79dca27 fix(build): restore Xcode 27 compilation`
- Scope: Preserved two pre-existing compile fixes before organization work began.
- Validation: macOS Debug build succeeded. The build reported two pre-existing Swift compiler warnings in `AppCommands.swift` and `SummarizeTodaysObservationsIntent.swift`.

### Phase 0 - Establish a trustworthy baseline

- Status: In progress
- Branch: `codex/repository-organization`
- Baseline commit: `b79dca27`
- Xcode: 27.0 beta (`27A5218g`)
- macOS Debug build: Passed
- iOS generic Debug build: In progress
- Full macOS test suite: Pending
- SwiftLint: Runs with Xcode beta but currently reports pre-existing violations, including errors. Its default traversal also enters ignored nested worktrees under `.claude/worktrees`; this must be corrected before treating repository-wide counts as a stable gate.
- Known compiler warnings:
  - `AppCore/AppCommands.swift`: closure stored in an `@Entry` may invalidate dependents on every update.
  - `Students/SummarizeTodaysObservationsIntent.swift`: main actor-isolated view initializer is called from a synchronous nonisolated context.

Commit target: `docs(repo): add incremental organization plan`

### Phase 1 - Repository hygiene

- Status: Pending

#### 1A - Stop tracking Xcode user data

- Remove tracked `xcuserdata` entries from Git while preserving local files.
- Verify `git ls-files '*xcuserdata*'` returns no paths.
- Commit target: `chore(git): stop tracking Xcode user data`

#### 1B - Consolidate documentation

- Move developer documentation out of the synchronized app source root.
- Merge the current `docs/` and `Maria's Notebook/Docs/` trees under repository-level `Documentation/`.
- Use `Architecture/`, `ADRs/`, `Implementation/`, `Manuals/`, and `Generated/` as the top-level documentation categories.
- Update relative links, scripts, README references, source comments, and stale directory maps.
- Commit target: `docs(repo): consolidate project documentation`

#### 1C - Define ownership conventions

- Document feature ownership and shared-layer boundaries.
- Commit target: `docs(architecture): define feature ownership conventions`

### Phase 2 - Consolidate Backup

- Status: Pending
- Move the archive implementation into `Backup/Archive/` without renaming Swift types.
- Commit target: `refactor(backup): consolidate archive implementation`

### Phase 3 - Co-locate Today

- Status: Pending
- Gather Today views, view models, and support code under one top-level feature.
- Commit target: `refactor(today): co-locate Today feature files`

### Phase 4 - Extract feature code from Components

- Status: Pending
- Move Todos first, then Notes and quick capture, one feature per commit.

### Phase 5 - Clarify shared layers

- Status: Pending
- Move feature-specific services and view models to their owning features while preserving genuinely cross-feature infrastructure.

### Phase 6 - Organize large flat features

- Status: Pending
- Organize Students, Work, and Presentations by subdomain, one feature per commit.

### Phase 7 - Mirror the test structure

- Status: Pending
- Reorganize tests so their folders mirror production feature ownership without renaming test types or methods.

### Phase 8 - Closeout and enforcement

- Status: Pending
- Refresh architecture documentation, add lightweight repository checks, remove superseded empty folders, and run final builds, lint, and tests.
