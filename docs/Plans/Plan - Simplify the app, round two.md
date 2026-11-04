# Simplify the app, round two

> **Not started.** Written 2026-11-03 from a whole-app analysis (branch `claude/app-simplification-analysis-31a526`): line and file counts per folder, live record counts read from the notebook over the Claude connection, the open rows in Tide, and what the first Simplify plan left alone on purpose.
> In short: one to-do list (Tide), the kept-but-empty features made cheap rather than deleted, about 60 Claude tools instead of 97, Settings as a list, the backup finished as one table, two template kinds instead of four, and the device-check backlog worked down and then capped, without touching the core loop (lesson, work, check-in, readiness, Class Grid).

## Goal

The first Simplify plan (`Plan - Simplify the app.md`, done 2026-10-19) made the app *look* smaller: fewer screens, aliased rows, one readiness rule. By design it changed no records, deleted no feature and kept every subsystem. The weight is now underneath, and this plan takes it out:

| Measure today | Count |
|---|---|
| Notebook Swift lines / files | 287,500 / 1,834 (tests 128,000) |
| Core Data entities | 93: 8 tombstones, 2 old Schedule types, 4 old Project template types |
| Claude tools | 97 across 56 files, 18,500 lines (the largest service) |
| SwiftUI views / sheets | 807 / 190 |
| Settings categories | 10 in 78 files, 12,400 lines |
| Open "Check on a device" rows in Tide | 135 (plus 11 Build & fix, 9 Review choices, 8 Release) |

Live record counts, read 2026-11-03:

| Feature | Records |
|---|---|
| Going Out, Procedures, Book Club sessions, Classroom Jobs | 0 each |
| Stories | 1 |
| Resources | 2 (one untitled) |
| Projects | 4, all dormant since 2026-04-01 |
| Practice sessions in the last 12 months | 2 |
| Notebook to-dos | 71, of which 24 are closed "[Moved to Tide]" copies |
| Reminders | 123; the same title appears two to five times (five copies of one January visit, "Plan Recess" twice, a plain copy beside a "synced from Apple Reminders" copy for most of September's) |
| Note templates | 24 seeded boilerplate lines ("Followed directions well"), two duplicated pairs |

Done means: the phases below are on main, the whole iOS suite passes, the Mac and Assistant build, and every "check on a device" line this plan produces is a row in Tide with the row's link here, not a copy.

## Progress

- [ ] Phase 0: Work the device-check backlog, then cap it (session: Danny with one helper session)
- [ ] Phase 1: One to-do list (session: fresh, Opus, feature-phase-deep)
- [ ] Phase 2: Empty features made cheap (session: fresh, Sonnet, feature-phase-light)
- [ ] Phase 3: About 60 Claude tools (session: fresh, Sonnet, feature-phase-light; after 1 and 2)
- [ ] Phase 4: Settings is a list (session: fresh, Sonnet, feature-phase)
- [ ] Phase 5: Backup finished as one table (session: fresh, Opus, feature-phase-deep)
- [ ] Phase 6: Two template kinds (session: fresh, Sonnet, feature-phase-light)
- [ ] Phase 7: Combine, full build, whole suite, cold review, land (session: the coordinating one)

Phases 1, 2, 4, 5 and 6 are independent and can run at once in their own worktrees; 3 waits for 1 and 2 (it removes tools they retire); 7 is last. Danny's cap from the first plan holds: three Opus agents at once across every session.

## Cost

Rough, by the first plan's experience (its 12 phases ran at about 1–8% of the weekly meter each):
- Phase 0 is Danny's time, not tokens, plus one small helper session.
- Phases 2, 3, 4, 6: ~1–2% each (Sonnet, patterned removals and merges with focused tests).
- Phases 1 and 5: ~5–8% each (Opus, data and backup format changes, their own reviews).
- Phase 7: ~3–4% (one full build, whole suite, an Opus review).
Total ~20–30% of a week, spread over as many days as Danny likes.

## Decisions

**What this plan changes from the first one, and why Danny has to say yes again**
- **Apple Reminders sync goes.** In October Danny chose "Reminders sync stays a Settings option; its doubles get fixed." Phase 9 of that plan stopped *new* doubles, but the 123 live reminders still carry the old ones, the Tide row asking whether the sync is on anywhere else is still open, and the feature costs an entity, nine files in `Services/Calendar`, a Settings pane, a Today section, a Claude tool and backup code. With Tide the list, Reminders is a third list for the same errands. This is the one reversal in the plan; Phase 1 does not start until Danny confirms it (open question 1).
- **Everything else keeps the first plan's decisions**: Going Out, Procedures, Schedules and Book Club stay because Danny will use them; the old Projects roles and templates stay in the model; retired destinations are aliased, never deleted; the iPhone tab bar doesn't change; Albums stays its own screen.

**Settled here, with why**
- **Tide is the to-do list.** The notebook keeps what only the notebook can make: automatic work check-ins ("Check in with Maya on …", which the first plan already kept out of Tide), follow-ups owed to a child (`list_open_follow_ups`), and Tide to-dos that name a child, shown on her page as today. Everything a person types as a to-do goes to Tide, as Phase 10 of the first plan already arranged. So the notebook's own Todos screen shrinks to the check-ins and the From Tide section, and subtasks, todo templates, priorities, someday, tags and the todo export go.
- **Retiring an entity means a tombstone, not a model edit.** CloudKit Production can't drop a record type and older builds may still write it, so `Reminder`, `TodoSubtask`, `TodoTemplate`, `ClassroomJob` and `JobAssignment` join `CoreDataStack.dormantTombstoneEntities` (`AppCore/Persistence/CoreDataStack+Model.swift:214`), their classes go, and the orphan cleanup leaves their rows alone. The eight existing tombstones show the pattern. No schema-version bump; nothing for Danny to deploy.
- **A backup still restores old files.** The backup stops *writing* a retired type (a format bump, as every removal is) and the importer treats a retired type's section as "known, skipped", so a 2026 backup restores without a warning about reminders it no longer has anywhere to put. Backups written before this plan keep their reminders; nothing is destroyed on disk.
- **Empty features are made cheap, not deleted.** Cheap means: no Claude tool until the feature has a record (Phase 3 removes them; adding one back is a half-hour job), the sidebar hides an empty Classroom row until its first record (the group already starts collapsed), and the code stays. Classroom Jobs is the exception: its folder is two entity files, it has no screen, and its only readers are two Claude tools and the monthly-report context builder, so it is retired outright.
- **Practice sessions fold into check-ins.** Two sessions in twelve months don't earn `Work/Practice` (2,781 lines), `PracticeSession` and its tool. A check-in gets an optional duration and the "noticed" signals (`madeBreakthrough`, `helpedPeer`, …) as its existing note tags; the two live sessions are copied into check-ins by a launch step and the entity becomes a tombstone. The practice stats on Work detail (`Work/Detail/PracticeStats.swift`) read check-ins instead.
- **Claude tools consolidate by subject, not by verb.** The seven `student_*` reads become one `student_record` with `sections:` (attendance, curriculum_map, meetings, observations, presentation_history, tracks, work). `list_lessons_by_area` folds into `find_lessons`; `list_orders`/`add_order_items`/`update_order_items` fold into `list_supplies`/`mark_supplies` with a stage; `set_timetable`/`change_schedule_day`/`weekly_schedules` stay (Schedules is live). Retired with their features: `list_reminders`, `classroom_jobs`, `assign_job`, `practice_sessions`, `list_going_outs`, `update_going_out`, `list_procedures`, `book_club`, `list_stories`, `add_project_session`, `project_detail`, `update_project` (Projects are dormant; `list_projects` stays so Claude can say so). Target: about 60. Every retired name is listed in `docs/Technical notes/MCP_SERVER.md` under "Retired", so a Cowork chat that names one gets a plain "that moved into …" answer from the server rather than an unknown-tool error.
- **Settings is a list.** The Dashboard (`Settings/Dashboard/`, 1,830 lines) becomes one status row (sync, backup, attention items) at the top of the list. The starfield, celebration burst, tap counter, What's New banner and notebook-stats card go (823 lines); `Attendance/Delight` (bells, birthday, welcome-back, hundredth-day confetti, 553 lines) goes with them. Ten categories become six: School Year, Classroom, Look & Feel (absorbs Messages), Templates, Sync & Backup (absorbs Troubleshooting), Intelligence (absorbs Connections). `SettingsCategory` keeps every raw value and aliases the retired ones, as `NavigationItem` does, because the selected category is persisted.
- **One model client.** `LocalModelClient` and `PrivateCloudModelClient` are constructed only by `AIClientRouter`, the Intelligence pane and the note-generation sheet. `FoundationModelClient` takes a `useCase` (on device / private cloud) and the two classes go, with `PrivateCloudSettingsView`. Apple Intelligence wording stays in `AppleIntelligenceMessages`.
- **Backup: the table drives both directions.** Phase C of the model-driven backup (`Backup/ModelRow.swift`, `Backup/ModelRowKinds.swift`, 40 specs) writes and restores 31 types, yet six `BackupDTOTransformers+*` files (770 lines) and seventeen `BackupEntityImporter+*` files (1,800 lines) still hand-write the other 60. Phase 5 moves every type to a `ModelRowSpec`, retires the hand-written files, and makes a schema change's backup step "add one spec line". The golden (`BackupGolden-v*.json`) and sparse-row fixtures are the safety net: re-record once, diff by hand, pin.
- **Two template kinds.** Meeting templates (two, built in) and sample work with steps stay. Note templates go: observations arrive by dictation and over the Claude connection in Danny's own voice, and the 24 seeded lines are not that voice. Todo templates go with Phase 1. `Settings/Templates/` keeps the meeting editor only; `BuiltInTemplateSeeder` seeds meetings only; `TemplatePickerView` leaves the note editor.
- **The core loop is untouched.** Lessons, presentations, work, check-ins, readiness, the Class Grid, Groups, Today's agenda and the four-section student page are where the app earns its keep. Nothing in this plan edits them beyond the check-in duration field.
- **Verification is part of done.** Phase 0 runs first because 135 unchecked rows means a third of recent work is unverified, and this plan would add to the pile. After it, the rule: a plan's status line may say Done only when its device rows are closed or explicitly dropped, and a session that would open its tenth device row stops and asks.

**Ruled out**
- Deleting Going Out, Procedures, Book Club, Stories, Resources or Projects (Danny's October answer stands).
- Writing Tide's `To do.md` files or joining its App Group (ruled out in the first plan, for the same reasons).
- Removing entities from the model or dropping CloudKit record types (Production can't; tombstones are the pattern).
- Rewriting the Class Grid, Lessons & Work or the student page (reviewed and redesigned in October; not where the weight is).
- Merging Lessons and Albums (ruled out in the first plan).
- Cutting tests to cut lines: tests stay unless the code they pin goes.

## Apple guidance

Checked 2026-11-03 against the iOS 27 / macOS 27 SDK in Xcode 27.2 (27B52); the Assistant's iOS 18 target is untouched by this plan.
- **Core Data entity removal**: a lightweight migration drops an entity's table, but `NSPersistentCloudKitContainer` keeps mirroring any record type that remains in the CloudKit schema, and older builds still write it, so Apple's guidance for shipped CloudKit schemas is additive changes only. Tombstones (entity kept, class and code removed) are the compatible path; this is what the app already does for eight types.
- **EventKit**: there is no API to revoke Reminders access. Turning the feature off means stop observing (`EKEventStoreChanged`), release reminder objects before the store, clear `eventKitReminderID`/`eventKitCalendarID` on the rows the tombstone keeps (a one-time launch step), and drop the `NSRemindersFullAccessUsageDescription` key and the Reminders entitlement so the privacy prompt never shows again.
- **FoundationModels**: `SystemLanguageModel(useCase:)` and `.default` cover on-device; Private Cloud Compute is not a separate client in the public API, which is why one `FoundationModelClient` suffices. Keep `#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)`.
- **Settings**: HIG [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) prefers a flat, grouped list with status inline over dashboards; a `NavigationSplitView` sidebar of six is within the "scan at a glance" guidance.
- **MCP**: the server's tool list is sent with every session, so fewer, subject-shaped tools with `sections:` arguments cost each Claude session less context; the server should answer a retired tool name with a plain message, not a protocol error.

## Testing rules for every phase

As in the first plan:
- **Never open Danny's live notebook.** Tests run on the leased iOS simulator only (`-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"`, `-parallel-testing-enabled NO`, one simulator); macOS is built (compile only), not run. Anything only the Mac app can show becomes a Tide row.
- **Never point a test at Tide's real server**; use the injected fake from Phase 10 (`Services/Tide/`).
- Builds and test runs take their turn in the build queue (`Scripts/locked_xcodebuild.sh`); each agent builds its smallest target and runs its `-only-testing:` suites (name the enclosing type for nested suites), and runs `~/.claude/bin/sim-lease --done` before reporting.
- A phase that retires a type re-records the backup golden once and reads the diff: only the retired section may change.

## Phase 0: Work the device-check backlog, then cap it

- Danny does one roll-out of main (the Hebrew birthdays row in Tide gates it: schema 21 must be in Production) and spends one sitting walking the 135 rows under "Check on a device" in `Areas/App Development/Cosmic Daybook/To do.md`, closing what passes and dropping what isn't worth checking.
- A helper session groups the rows by screen beforehand (`get_area`, then a short list in chat: Today rows, Attendance rows, …) so the walk goes screen by screen, and closes rows on Danny's word (`complete_action` / `drop_action`).
- Then the cap: this plan's `## Ending a phase` says a phase opens at most three device rows; the repo's `CLAUDE.md` gets one line under Build board saying a plan is Done only when its device rows are closed.
- Done when: fewer than 20 device rows are open and the CLAUDE.md line is on main.

## Phase 1: One to-do list

- Confirm open question 1 with Danny first.
- **Reminders off**: delete `Services/Calendar/ReminderSyncService*.swift`, `EventKitMirror+UnlinkedReminders.swift`, `EventKitMirror+OldRows.swift` and the reminder paths in `EventKitMirror.swift`/`EventKitChangeObserver.swift` (calendar events stay: `CalendarSyncService` still mirrors EventKit events for Today); `Settings/Sync/ReminderSyncSettingsView.swift`; `Today/Views/Sections/TodayViewRemindersSection.swift` and the reminder arrays in `TodayViewModel`/`TodayDataFetcher`/`TodayEventKitSync`; `Models/ReminderEntity.swift` and the `.reminder` case in `Notes/Editor/UnifiedNoteEditor.swift` and `CDUnifiedNotes+Helpers.swift`; the reminder dedup in `Services/Migrations/DataCleanupService+DeduplicateRecords.swift` and `+SameSourceMerges.swift`; `list_reminders` in `MCPNotebookTools+Library.swift`; the reminder stats in `SettingsStatsViewModel`; `UserDefaultsKeys` entries; the sample-classroom reminders. `Reminder` joins `dormantTombstoneEntities`. A launch step clears the EventKit ids on existing rows and removes the Reminders usage string and entitlement.
- **Todos slimmed**: `TodoSubtask` and `TodoTemplate` become tombstones; `Todos/Views/TodoTemplatesView.swift`, `Todos/Support/TodoTemplateUse.swift`, `Todos/Services/TodoExportService.swift`, the subtask rows in `NewTodoForm` and the detail, and priority/someday/tag fields leave the form (the entity keeps the columns; the UI stops showing them). `TodoMainView+Sidebar.swift` lists: Check-ins, From Tide, Done. `update_todo` loses the fields that went; `list_todos` keeps its filters that still apply.
- **The 24 "[Moved to Tide]" rows** and the other closed notebook to-dos stay as history; nothing is deleted from the store.
- **Backup**: `Reminder`, `TodoSubtask`, `TodoTemplate` leave `BackupEntityTable` as written types and join a "known, skipped on import" list; format bump; golden re-recorded.
- Done when: notebook, Mac and Assistant build; `TodoTests`, `TideSyncTests`, `TodayDataFetcherTests`, `BackupGoldenOutputTests`, `BackupSparseRowTests` and a new `RetiredTypesRestoreTests` (an old backup with reminders restores clean) pass; the Mac look of Todos and the Tide round trip are Tide rows.

## Phase 2: Empty features made cheap

- **Classroom Jobs retired**: `ClassroomJobs/` deleted; `ClassroomJob`, `JobAssignment` tombstones; `MCPNotebookTools+Jobs.swift` deleted; `ParentReports/Services/MonthlyReportContextBuilder.swift` drops the jobs paragraph; `StudentDeletion` and `DataCleanupService+ShelfDeduplication` drop their jobs steps; backup as in Phase 1.
- **Practice folded into check-ins**: `WorkCheckIn` gains optional `durationMinutes` (schema 23, additive, a Production deploy step for Danny) and reuses its note for the signals as tags; `Work/Practice/` deleted (`PracticeSessionCard*`, the sheet, the service); `Components/Shared/PracticeSessionCompactRow.swift` goes; `Work/Detail/WorkDetailView+PracticeTracking.swift` and `PracticeStats.swift` read check-ins; `LessonJourneyTimeline`, `CurriculumMapLoader`, `LessonAssignmentDetailSheet(+WorkSummary)`, `PresentationSessionCommit+LeftBehindWork`, `StudentAnalysisService` and `MonthlyReportContextBuilder` switch their practice reads to check-ins; a launch step in `MigrationRunner` copies the two live sessions into check-ins, idempotent by session id in the check-in note; `PracticeSession` tombstone; `practice_sessions` tool deleted.
- **Hide empty rows**: `RootView.NavigationGroup` gets a per-item `isShown` that `RootView` evaluates once per launch and on save for Going Out, Clubs & Projects (Projects *or* Book Club sessions) and Resources' Procedures type: shown when a record exists. The row's `NavigationItem` case stays; a saved selection on a hidden row lands on Today (the first plan's rule for retired items).
- Done when: builds pass; `NavigationGroupTests` pins the hiding rule; `WorkCheckInTests` covers the duration and the copy step; the Classroom group on iPad with no Going Outs is a Tide row.

## Phase 3: About 60 Claude tools

- After Phases 1 and 2. In `Services/MCPServer/`: `student_record` (one file) replaces the seven `student_*` reads, each old file's body becoming a section builder; `find_lessons` absorbs `list_lessons_by_area`; Orders tools fold into Supplies tools; `MCPNotebookTools+Jobs`, `+Practice`, the going-out, procedures, book-club, stories and project-session/detail/update tools are deleted; `list_projects` stays.
- A `retiredTools: [String: String]` table in the server answers an old name with "`student_work` moved into `student_record` with `sections: ["work"]`" as a tool error message in plain words.
- `Daybook Assistant/` and the `Scripts/mcp` bridge are unaffected (they don't list tools).
- `docs/Technical notes/MCP_SERVER.md` is rewritten to the new list with a Retired section; a test under `Cosmic Daybook Tests/Services` pins the count.
- Done when: the server lists about 60 tools; every existing MCP test that named a retired tool is moved to the new one or deleted with it; one Cowork round trip against the Release Mac app is a Tide row.

## Phase 4: Settings is a list

- `Settings/Dashboard/` shrinks to `SettingsDashboardView` (one status row + `SettingsAttention`) and `SettingsCategoryIcon`; `CosmicStarfield`, `SettingsCelebration`, `SettingsWhatsNew`, `WhatsNewBanner`, `SettingsNotebookStatsView`, `SettingsStatsViewModel`, `SettingsEmptyState`, `SettingsFooterView` deleted; `Attendance/Delight/` deleted and its call sites in the attendance tile and sheet removed.
- `SettingsCategory` goes to six cases with aliases for `overview`, `messages`, `connections`, `troubleshooting`; `SettingsView+Sections.swift` moves their rows into the absorbing panes.
- `Services/AI/LocalModelClient.swift`, `PrivateCloudModelClient.swift` and `Settings/Intelligence/PrivateCloudSettingsView.swift` deleted; `FoundationModelClient` takes the use case; `AIClientRouter`, `SettingsIntelligencePane` and `Students/Notes/AppleIntelligenceSheet+Generation.swift` use it.
- Done when: builds pass; `SettingsCategoryTests` pins the six cases and the aliases; `AIClientRouterTests` passes; Settings on the Mac and the iPhone More › Settings list are Tide rows.

## Phase 5: Backup finished as one table

- Every type in `BackupEntityTable` gets a `ModelRowSpec` in `ModelRowKinds.swift` (about 50 new specs); `BackupDTOTransformers+Core/+Work/+Misc/+Albums/+V18Entities.swift` and all `BackupEntityImporter+*.swift` except `+ModelRows.swift` and `+Assets.swift` (files on disk are not rows) are deleted; `BackupNoteLinks.swift` becomes a spec `parents` rule.
- Order of work: one entity family per commit (Students, Lessons, Work, Calendar, Projects, Resources, Albums, …), re-recording the golden only at the end and reading the diff: byte-identical except key order where the old code wasn't deterministic.
- `docs/Technical notes/BACKUP_SYSTEM.md` documents "a new entity = one spec line + one golden re-record".
- Done when: all 19 backup suites pass; the golden diff is reviewed in the PR description; a Merge restore of a real backup on the iPad is a Tide row.

## Phase 6: Two template kinds

- `NoteTemplate` tombstone; `Settings/Templates/NoteTemplateEditorSheet.swift`, `NoteTemplateManagementView.swift`, the generic `TemplateEditorSheet`/`TemplateManagementView` if only notes used them, `Notes/Editor/TemplatePickerView.swift` and its button in `NoteEditorSections.swift`, `Repositories/NoteTemplateRepository.swift`, the note-template dedup in `DataCleanupService+Deduplication`/`+SameSourceMerges` deleted; `BuiltInTemplateSeeder` seeds meeting templates only; `list_templates` loses `note` and `todo` kinds.
- `SettingsTemplatesPane` shows Meeting templates and Sample work.
- Done when: builds pass; `TemplateSeederTests` and `NoteEditorTests` pass; the note editor on iPhone without the template button is a Tide row.

## Phase 7: Combine, full build, whole suite, cold review, land

- Merge the phase branches onto one branch in order 1, 2, 3, 5, 4, 6; one full notebook build (iOS and Mac), one Assistant build, the whole iOS suite once.
- An Opus review of the combined diff split by phase, reading for: a retired type still fetched somewhere, a Today section that now never hides, a saved selection that lands on a hidden row, a backup that fails to restore an old file, a Claude tool name used by `.claude/skills/` or Cowork prompts in the repo.
- Update `Cosmic Daybook/CLAUDE.md` (entity counts, tool count, Settings categories, Project Structure tree), `docs/Technical notes/DATA_MODELS.md` (tombstone list), this plan's status line, and run `~/.claude/bin/docs-index`.
- Land on main; not rolled out by this plan (roll-out is its own Tide row, gated on the schema 23 deploy from Phase 2).

## Starting a phase

- Read this plan's Decisions and the phase; read `Plan - Simplify the app.md` › Decisions for the rules it inherits.
- Make the worktree, build once before editing (the prefix-mapping settings in `CLAUDE.md`), lease the simulator.
- Mark the phase in Progress above and on the build board (`build-board` skill).

## Ending a phase

- Smallest build + `-only-testing:` suites green; `sim-lease --done`.
- Progress line above updated with what differed from the plan and why; at most three device rows, each a Tide row in `Areas/App Development/Cosmic Daybook/To do.md` under "Check on a device" with the row's `tide://` link here.
- Board updated.

## Open questions

1. **Reminders sync off** (Phase 1 gate). It reverses October's "stays a Settings option". The Tide row "Tell Claude whether Reminders sync is on in Cosmic Daybook on more than one of my devices" is still open; if the answer is "it's on and I use it from my phone", Phase 1 keeps Reminders and retires only todo subtasks and templates.
2. **Practice sessions into check-ins** (Phase 2). Two records in a year says yes; if Danny means to start recording practice this winter, the folder stays and only the Claude tool is dropped.
3. **Track, TrackStep, SequenceTrack and StudentTrackEnrollment beside YearPlanEntry and LessonSequenceSettings** look like two generations of one idea (`Students/Progress` reads the Track family in seven files; `Services/Progression` reads both). Danny sent this question to another session on 2026-11-03; its answer decides whether a Phase 8 (one sequence model) is added here or becomes its own plan. Not blocking.
4. **What's New**: Phase 4 removes the banner. If Danny reads it after each roll-out, keep `WhatsNewBanner` as one row at the top of the list and drop only the rest.
