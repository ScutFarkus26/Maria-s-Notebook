# Repository Organization Plan

This log governs the incremental repository reorganization. The work is intentionally split into small, independently reversible commits. File moves must not include type renames, formatting sweeps, or behavior changes.

## Validation rules

Every organization commit must:

1. Cover one coherent area.
2. Update affected documentation and path references in the same commit.
3. Pass `git diff --cached --check`.
4. Run SwiftLint with `Maria's Notebook/.swiftlint.yml`; while the recorded baseline has violations, changed Swift files must introduce none.
5. Preserve the macOS and iOS build baselines.
6. Run relevant tests, with the full suite at phase boundaries.
7. Record validation results, exceptions, and the commit below.

Build commands use Xcode 27 beta at `/Applications/Xcode-beta.app/Contents/Developer` without changing the machine-wide `xcode-select` setting.

## Execution log

### Preflight checkpoint

- Status: Complete
- Commit: `b79dca27 fix(build): restore Xcode 27 compilation`
- Scope: Preserved two pre-existing compile fixes before organization work began.
- Validation: macOS Debug build succeeded. The build reported two pre-existing Swift compiler warnings in `AppCommands.swift` and `SummarizeTodaysObservationsIntent.swift`.

### Phase 0 - Establish a trustworthy baseline

- Status: Complete
- Branch: `codex/repository-organization`
- Baseline commit: `b79dca27`
- Plan commit: `9bc5a837`
- Xcode: 27.0 beta (`27A5218g`)
- macOS Debug build: Passed
- iOS generic Debug build: Passed
- Full macOS test suite: 161 passed and 11 failed out of 172. All 11 failures are backup tests blocked by the same local Keychain write error, `-34018`; this is the recorded pre-existing test baseline.
- SwiftLint: Runs with Xcode beta and the project configuration, but currently reports pre-existing violations, including errors. Later phases must not add violations to changed Swift files.
- Known compiler warnings:
  - `AppCore/AppCommands.swift`: closure stored in an `@Entry` may invalidate dependents on every update.
  - `Students/SummarizeTodaysObservationsIntent.swift`: main actor-isolated view initializer is called from a synchronous nonisolated context.

Commit: `9bc5a837 docs(repo): add incremental organization plan`

### Phase 1 - Repository hygiene

- Status: Complete
- Closeout validation: macOS and generic iOS Debug builds passed after the documentation move. Local Markdown links, workspace XML, entitlements, and manual-generator syntax checks passed. The macOS test result remains at the recorded Phase 0 baseline: 161 passed and 11 Keychain-blocked backup failures.

#### 1A - Stop tracking Xcode user data

- Status: Complete
- Commit: `6dc6a065`
- Remove tracked `xcuserdata` entries from Git while preserving local files.
- Verify `git ls-files '*xcuserdata*'` returns no paths.
- Commit target: `chore(git): stop tracking Xcode user data`

#### 1B - Consolidate documentation

- Status: Complete
- Commit: `ecee4122`
- Validation: Local Markdown links resolved; manual generators parsed; workspace XML and entitlements validated; macOS and generic iOS builds passed. Xcode confirmed the old developer documents were removed from app resources.
- Move developer documentation out of the synchronized app source root.
- Merge the current `docs/` and `Maria's Notebook/Docs/` trees under repository-level `Documentation/`.
- Use `Architecture/`, `ADRs/`, `Implementation/`, `Manuals/`, and `Generated/` as the top-level documentation categories.
- Update relative links, scripts, README references, source comments, and stale directory maps.
- Commit target: `docs(repo): consolidate project documentation`

#### 1C - Define ownership conventions

- Status: Complete
- Commit: `e24f22b5`
- Document feature ownership and shared-layer boundaries.
- Commit target: `docs(architecture): define feature ownership conventions`

### Phase 2 - Consolidate Backup

- Status: Complete
- Commit: `e6e7dcaa refactor(backup): consolidate archive implementation`
- Moved the six current AppleArchive files from `Backup2/` into `Backup/Archive/` without renaming declarations or changing behavior.
- Moved `BACKUP_SYSTEM.md` from the synchronized app source tree into `Documentation/Architecture/` and repaired code comments, README links, and documentation paths.
- Validation:
  - macOS Debug build passed.
  - Generic iOS Debug build passed.
  - Thirteen backup coverage, registry, field-coverage, and checkpoint-safety tests passed.
  - Five archive compatibility tests passed; the other eleven targeted round-trip tests failed only with the recorded Keychain error, `-34018`.
  - The full macOS suite exactly matched the established baseline: 161 passed and the same 11 Keychain-blocked tests failed.
  - Local Markdown links and staged whitespace checks passed. Changed-file SwiftLint reported only the repository's recorded pre-existing violations.
- Intentional exception: the existing `Backup2RoundTripTests` type and references to that test type remain unchanged because this phase forbids type renames. Test naming can be addressed with the Phase 7 test-structure work.

### Phase 3 - Co-locate Today

- Status: Complete
- Implementation commit: `e86b9bb6` (`refactor(today): co-locate Today feature files`)
- Gathered 35 Today-owned Swift files under one top-level feature: views in `Today/Views/`, the primary view model in `Today/ViewModels/`, and builders, loaders, caches, types, and navigation support in `Today/Support/`.
- Preserved shared ownership for `Models/TodayAgendaOrderEntity.swift` and `Students/SummarizeTodaysObservationsIntent.swift`; neither belongs exclusively to the Today presentation feature.
- The source diff is 35 100% renames with zero insertions or deletions. No types, declarations, imports, or behavior changed.
- Updated the repository maps and developer manual to reflect the new Today ownership boundary and removed stale Today paths.
- Validation:
  - The macOS build completed successfully as part of the full test run, and the generic iOS build passed.
  - The full macOS suite exactly matched the established baseline: 161 passed and the same 11 Keychain-blocked tests failed with `-34018`.
  - Staged whitespace checks passed. SwiftLint reported only the existing file-length warnings in three unchanged Today source files.

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
