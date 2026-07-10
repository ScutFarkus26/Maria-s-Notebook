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
  - `Students/Notes/SummarizeTodaysObservationsIntent.swift`: main actor-isolated view initializer is called from a synchronous nonisolated context.

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
- Preserved shared ownership for `Models/TodayAgendaOrderEntity.swift` and `Students/Notes/SummarizeTodaysObservationsIntent.swift`; neither belongs exclusively to the Today presentation feature.
- The source diff is 35 100% renames with zero insertions or deletions. No types, declarations, imports, or behavior changed.
- Updated the repository maps and developer manual to reflect the new Today ownership boundary and removed stale Today paths.
- Validation:
  - The macOS build completed successfully as part of the full test run, and the generic iOS build passed.
  - The full macOS suite exactly matched the established baseline: 161 passed and the same 11 Keychain-blocked tests failed with `-34018`.
  - Staged whitespace checks passed. SwiftLint reported only the existing file-length warnings in three unchanged Today source files.

### Phase 4 - Extract feature code from Components

- Status: Complete
- Implementation commits:
  - `1b14621b` (`refactor(todos): move Todo UI out of Components`)
  - `ac057e7c` (`refactor(notes): co-locate note UI and quick capture`)
- Moved 30 Todo-owned Swift files into `Todos/Views/` and `Todos/Support/`, including the Todo screens, forms, rows, scheduling controls, filters, sorting, and date parser.
- Moved 26 note-owned Swift files into `Notes/Editor/`, `Notes/Observations/`, `Notes/QuickCapture/`, and `Notes/Views/`. This also removed the feature-specific note editor and tag picker from `AppCore`.
- Both source changes are 100% renames with zero Swift insertions or deletions. No types, declarations, imports, or behavior changed.
- Preserved shared ownership for controls used by unrelated features, including `Components/SelectedStudentChipsRow.swift`. The cross-feature quick-action button and work-item sheet remain in `AppCore` as application composition.
- Updated repository maps, the developer manual, and AI and architecture documentation for the new paths and feature boundaries.
- Validation:
  - macOS and generic iOS Debug builds passed after each implementation commit.
  - The full macOS suite exactly matched the established baseline: 161 passed and the same 11 Keychain-blocked tests failed with `-34018`.
  - Staged whitespace and stale-path checks passed.
  - SwiftLint reported no Notes violations and only six pre-existing Todo warnings in unchanged, rename-only source files.

### Phase 5 - Clarify shared layers

- Status: Complete
- Implementation commits:
  - `28fcebd4` (`refactor(viewmodels): move feature state to owners`)
  - `d47a9ac3` (`refactor(services): move feature logic to owners`)
- Moved six feature-owned view-model files from the shared `ViewModels/` folder into Lessons, the Lessons checklist, and Topics. `ViewModels/CommandBarViewModel.swift` remains because the command bar is app-wide.
- Moved 37 feature-specific service and planning-state files into Chat, Inbox, Parsha, Planning, Presentations, Procedures, Projects, Students, Supplies, Todos, and Work.
- All 43 Swift changes are 100% renames with zero Swift insertions or deletions. No types, declarations, imports, or behavior changed.
- Preserved the shared `Services/` layer for cross-feature infrastructure and integrations: AI clients and routing, CloudKit and sync, migrations, calendar and reminders, search, persistence history, networking, and app-wide utilities.
- Intentional shared exceptions: progression orchestration (`LessonProgressionRules`, `ReadinessAutoUnlockService`, `SequenceAutoPopulateService`, `SequenceTrackService`, `TrackProgressResolver`, and `UnlockNextLessonService`) remains shared because it coordinates Lessons, Planning, Presentations, Students, and Work rather than having one clear owner.
- Updated repository maps, service documentation, and AI file maps to reflect the new ownership boundaries.
- Validation:
  - macOS and generic iOS Debug builds passed after each implementation commit.
  - The full macOS suite exactly matched the established baseline: 161 passed and the same 11 Keychain-blocked tests failed with `-34018`.
  - Local Markdown links, staged whitespace checks, and moved-path checks passed.
  - SwiftLint reported no violations in the moved view-model files and only 19 pre-existing warnings in unchanged, rename-only service files.

### Phase 6 - Organize large flat features

- Status: Complete
- Implementation commits:
  - `c123e1ea` (`refactor(students): organize feature by subdomain`)
  - `dcef63af` (`refactor(work): organize feature by subdomain`)
  - `14daaa04` (`refactor(presentations): organize feature by subdomain`)
- Moved all 107 flat Students Swift files into detail, files, import, insights, meetings, models, notes, presentations, printing, progress, roster, and selection subdomains. Existing LessonDetail, Recall, and YearPlan subdomains were preserved.
- Moved all 58 flat Work Swift files into agenda, check-ins, completion, detail, models, practice, sample-work, steps, and support subdomains. Existing Services and WorkCard subdomains were preserved.
- Moved all 41 flat Presentations Swift files into assignments, overview, planning, and workflow subdomains. The existing Services subdomain was preserved.
- All 206 Swift changes are 100% renames with zero Swift insertions or deletions. No types, declarations, imports, or behavior changed, and the three feature roots now contain no Swift files.
- Updated developer, data-model, implementation, and integration documentation for the new paths and feature maps.
- Validation:
  - macOS and generic iOS Debug builds passed after each feature commit.
  - The full macOS suite exactly matched the established baseline: 161 passed and the same 11 Keychain-blocked tests failed with `-34018`.
  - Local Markdown links, staged whitespace checks, moved-path checks, and empty feature-root checks passed.
  - SwiftLint reported no new violations; the moved files retain 35 pre-existing warnings and no errors.

### Phase 7 - Mirror the test structure

- Status: Complete
- Implementation commit: `d1247d74` (`refactor(tests): mirror production ownership`)
- Moved all 26 flat test Swift files into Attendance, Backup, Notes, Parsha, Presentations, SchoolYear, Sharing, Students/Recall, Work, AppCore, Services/Sync, Utils/CSV, and Support folders.
- All test source changes are 100% renames with zero Swift insertions or deletions. No test type, suite, or method names changed, so existing `-only-testing` identifiers remain valid.
- The test target root now contains no loose Swift files. Shared helpers and bundle lookup live in `Support/`.
- Updated backup documentation paths for the new test locations.
- Validation:
  - The generic iOS Debug build passed.
  - The macOS test action compiled every moved file from its new folder, confirming synchronized-folder target membership.
  - The full macOS suite exactly matched the established baseline: 161 passed and the same 11 Keychain-blocked tests failed with `-34018`.
  - Local Markdown links, staged whitespace checks, moved-path checks, and the empty test-root check passed.
  - Because every Swift file is a 100% rename, the reorganization introduces no SwiftLint changes.

### Phase 8 - Closeout and enforcement

- Status: Pending
- Refresh architecture documentation, add lightweight repository checks, remove superseded empty folders, and run final builds, lint, and tests.
