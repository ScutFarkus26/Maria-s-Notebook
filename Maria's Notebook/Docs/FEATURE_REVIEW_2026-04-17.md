# Feature Review — 2026-04-17

## Scope and method

This report is a **static, read-only code review** of every feature module in Maria's Notebook, plus a verification of the four "known-issue" documents at the repo root. It was produced from a Linux environment with **no Swift toolchain available**, so:

- **Nothing was built or executed.** No `xcodebuild`, no `swift build`, no test run, no formatter or linter pass.
- **All findings are inferred from reading source.** Static review can flag logic bugs, broken contracts, dead code, and pattern-level defects, but it cannot prove the absence of bugs and cannot detect runtime crashes, threading races, or SwiftData query-time failures with certainty. Treat HIGH findings as "high suspicion" until reproduced on a Mac.
- **Coverage:** ~370 Swift files across 19 feature modules + shared infrastructure (`AppCore`, `Models`, `Services`, `Components`, `ViewModels`, `Utils`).

Findings were produced by six parallel review passes:

| Pass | Scope |
|------|-------|
| Batch 1 | `Students/`, `Lessons/`, `Presentations/`, `Topics/` |
| Batch 2 | `Work/`, `Inbox/`, `Procedures/` |
| Batch 3 | `Attendance/`, `Agenda/`, `Schedules/`, `Planning/`, `Community/`, `Logs/` |
| Batch 4 | `Backup/`, `Settings/`, `Repositories/`, `Issues/`, `Supplies/`, `Projects/` |
| Batch 5 | Cross-cutting (`AppCore/`, `Models/`, `Services/`, `Components/`, `ViewModels/`, `Utils/`) |
| Phase B | Verification of `CRITICAL_ISSUE_RAWCODABLE.md`, `PHASE_2_BLOCKED.md`, `PHASE_3_INCIDENT_REPORT.md`, `TECHNICAL_DEBT.md` |

---

## Executive summary

**Findings: 14 HIGH, 30 MED, 4 LOW.**

### Biggest risks

1. **Backup encryption is effectively disabled.** `Settings/SettingsViewModel.swift:95` hardcodes the password to `"defaultPassword"` whenever `encryptBackups` is true. Every "encrypted" backup is decryptable by anyone who reads the source. This single defect dominates the safety story.
2. **Restore can leave the database empty.** `Backup/BackupService.swift:255-259` deletes all data before importing in replace mode and never snapshots the current DB first. If import fails mid-stream, there is no recovery point.
3. **Work step mutations are not persisted.** `Work/WorkStepRow.swift:58`, `Work/WorkStepEditorSheet.swift:67` and `:79` call into `WorkStepService` but never call `save()`. Edits, completions, and deletes appear to succeed but vanish on app restart.
4. **The work completion contract is broken.** `Work/WorkCompletionBackfill.swift` is defined but never called. `Work/WorkDetailViewModel.swift:204` transitions status to `.complete` without writing a `WorkCompletionRecord`, contradicting the documented active → review → complete lifecycle.
5. **`@MainActor`-violating mutations on `WorkCheckIn`.** Three methods in `Work/WorkCheckIn.swift:95-114` are declared `nonisolated` but mutate `self` on a `@Model` — a SwiftData concurrency-rule violation that will at minimum produce data races under load.

### What looks healthy

- **Known-issue docs check out.** `@RawCodable`, `@CloudKitUUID`, and the Phase 3 schema regression are all confirmed **FIXED** in the live code (see § Known-issue verification).
- **Navigation is complete.** All 19 documented feature modules have routes wired in `AppCore/RootView.swift` and `AppRouter.swift`.
- **ModelContainer registration is complete.** All 44 `@Model` classes registered in `AppCore/AppSchema.swift:23-47`.
- **Foundation Models / AI integration is properly gated** via `#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)` plus `#available` checks. Devices without it will not crash.
- **Date/time handling in classroom modules is sound.** Calendar, attendance, and community code respects `startOfDay` and time-zone boundaries.

---

## Per-feature findings

### Students/

| Sev | Location | Finding |
|---|---|---|
| HIGH | `Students/StudentLessonDetailViewModel.swift:6` | `@Observable` ViewModel without `@MainActor`; managed UI state may be touched off-main. |
| MED | `Students/StudentCardComponents.swift:536` | `randomElement()!` on a literal array — crashes if it's ever empty. |
| MED | `Students/StudentDetailView.swift:176` | `try?` on `repository.deleteStudent` swallows failure; user sees no error. |
| MED | `Students/StudentLessonDraftSheet.swift:28` | `try?` on `modelContext.save()` after deletion; silent failure. |
| MED | `Students/StudentInsightsView.swift:436` | `try?` on `modelContext.save()`; silent failure. |
| MED | `Students/StudentLessonPill.swift:205-206` | Force-unwrap inside predicate (`$0.givenAt!`) is correct after the nil check but unidiomatic. |

### Lessons/

| Sev | Location | Finding |
|---|---|---|
| MED | `Lessons/LessonAttachmentImporter.swift:20` | `try?` on lesson fetch returns `[]` on failure; hides data-access errors. |
| MED | `Lessons/LessonOrderMigration.swift:57,87,114` | Three `try?` on `context.save()` inside migration code; migration failures are silent. |
| MED | `Lessons/LessonDetailView.swift:87` | `try?` on `repository.deleteLesson`; user sees no error. |
| LOW | `Lessons/LessonPickerComponents.swift:4` | `// TODO` to extract formatting/selection helpers into `GiveLessonViewModel` for testability. |

### Presentations/

| Sev | Location | Finding |
|---|---|---|
| MED | `Presentations/UnifiedPresentationWorkflowPanel.swift:818` | Force-unwrap of dictionary subscript (`workDrafts[studentID]![index]`) after a guard; should bind. |
| MED | `Presentations/PresentationsView.swift:259` | `try?` on `modelContext.save()` after editing `scheduledFor`. |
| MED | `Presentations/PresentationProgressListView.swift:16` | `try?` on `context.fetch` returning nil; hides errors. |
| MED | `Presentations/LessonAssignmentDetailSheet.swift:565` | `try?` on save; silent failure. |
| MED | `Presentations/LessonAssignmentHistoryView.swift:620` | `try?` on save; silent failure. |

### Topics/

No findings.

### Work/

| Sev | Location | Finding |
|---|---|---|
| HIGH | `Work/WorkStepRow.swift:58` | `toggleCompletion()` called on `WorkStepService` but no `modelContext.save()` follows; toggle is lost on relaunch. |
| HIGH | `Work/WorkStepEditorSheet.swift:67` | `update()` called on `WorkStepService`; no save follows. |
| HIGH | `Work/WorkStepEditorSheet.swift:79` | `delete()` called on `WorkStepService`; no save follows. |
| HIGH | `Work/WorkCompletionBackfill.swift:1` | Service defined but never instantiated or called anywhere; historical `WorkCompletionRecord` entries are never written. |
| HIGH | `Work/WorkCheckIn.swift:95` | `nonisolated func markCompleted(...)` mutates `self` on a `@Model`; violates SwiftData concurrency rules. |
| HIGH | `Work/WorkCheckIn.swift:102` | `nonisolated func reschedule(...)` mutates `self`. Same violation. |
| HIGH | `Work/WorkCheckIn.swift:109` | `nonisolated func skip(...)` mutates `self`. Same violation. |
| MED | `Work/WorkDetailViewModel.swift:204` | `save()` does not write a `WorkCompletionRecord` when status transitions to `.complete`. Breaks documented lifecycle contract. |
| MED | `Work/WorkDetailViewModel.swift:204` | `save()` does not update `lastTouchedAt` on mutation; `WorkAgingPolicy` reads stale data. |

### Inbox/

| Sev | Location | Finding |
|---|---|---|
| LOW | `Inbox/InboxSheetView.swift:100` | `try? await Task.sleep(...)` — fire-and-forget delay; acceptable but worth noting. |

### Procedures/

No findings.

### Attendance/

| Sev | Location | Finding |
|---|---|---|
| HIGH | `Attendance/AttendanceEmail.swift:135` | `composerForCurrentPrefs` presents `MailComposerView` with empty `toRecipients` if `storedToAddress` is none; no validation. |
| MED | `Attendance/AttendanceEmail.swift:94` | `parseRecipients(_:)` exists but is unused; multi-recipient support is not actually wired (matches `TECHNICAL_DEBT.md`). |
| MED | `Attendance/AttendanceEmail.swift:310` | `// TODO` for cancellation timeout fallback in macOS sharing-service delegate. |

### Agenda/

| Sev | Location | Finding |
|---|---|---|
| HIGH | `Agenda/AgendaSlot.swift:369-370` | `try?` swallows fetch errors when loading lesson and student during drop; auto-enrollment downstream silently uses nil. |
| MED | `Agenda/AgendaSlot.swift:391` | `try? modelContext.save()` after reorder; user sees no error if save failed. |
| MED | `Agenda/CalendarMonthGridView.swift:85-106` | Multiple uncoordinated `Task` blocks toggling non-school days; concurrent toggles on the same date can race. |

### Schedules/

| Sev | Location | Finding |
|---|---|---|
| LOW | `Schedules/SchedulesView.swift:121` | `safeSave()` after delete with no user feedback path. |

### Planning/

| Sev | Location | Finding |
|---|---|---|
| MED | `Planning/PlanningWeekViewContent.swift:114` | `Task { @MainActor in itemFrames = frames }` inside a `PreferenceKey` observer; concurrent layout passes can race. |
| MED | `Planning/PlanningActions.swift:7` | `Task { @MainActor in context.safeSave() }` after `moveToInbox` is fire-and-forget; caller cannot detect failure. |

### Community/

| Sev | Location | Finding |
|---|---|---|
| LOW | `Community/CommunityMeetingsView.swift:101-102` | Comment says `NavigationStack` removed; sheet presentation could conflict if a parent re-introduces it. |

### Logs/

| Sev | Location | Finding |
|---|---|---|
| MED | `Logs/AttendanceLogView.swift:44-46` | `.uniqueByID` keeps first occurrence only; later CloudKit-synced updates are silently dropped. |
| MED | `Logs/MeetingsLogView.swift:39-40` | Same `uniquingKeysWith` pattern; same silent-data-loss risk. |

### Backup/

| Sev | Location | Finding |
|---|---|---|
| HIGH | `Backup/Export/BackupCodec.swift:129` | Force-unwrapped `password.data(using: .utf8)!` — unreachable in practice but a crash vector if invariants change. |
| HIGH | `Backup/Export/BackupCodec.swift:212` | Same force-unwrap inside KDF. |
| HIGH | `Backup/BackupService.swift:255-259` | Replace-mode restore calls `deleteAll()` before importing without snapshotting current DB; failed import leaves an empty database. |
| HIGH | `Backup/BackupService.swift:417` | `envelope.formatVersion` is never validated against supported version range; unsupported formats proceed to import. |
| MED | `Backup/Services/SmartRetentionManager.swift:189` | `age <= policy.keepAllRecentDays` is off-by-one vs. the comment ("< 3 days"). |
| MED | `Backup/BackupService.swift:172` | `try?` on `setAttributes(...0o600)` — encrypted backups may end up world-readable if attribute set fails. |
| MED | `Backup/BackupService.swift:522` | `try? modelContext.delete(model: type)` during restore; silent failure path. |

### Settings/

| Sev | Location | Finding |
|---|---|---|
| HIGH | `Settings/SettingsViewModel.swift:95` | Hardcoded `"defaultPassword"` used when `encryptBackups` is true. Encryption is effectively disabled. |

### Repositories/

No findings.

### Issues/

No findings.

### Supplies/

No findings.

### Projects/

No findings.

---

## Cross-cutting findings

| Sev | Location | Finding |
|---|---|---|
| HIGH | `AppCore/AppDependencies.swift:346-356` | `AppDependencies.makeTest()` builds a `ModelContainer` with only 4 models (`Student`, `Lesson`, `WorkModel`, `Note`) versus 44 in production, and registers no services. Integration tests that touch any other model (`StudentLesson`, `WorkCheckIn`, `WorkStep`, `Issue`, etc.) or any service will crash. *Verify this on a Mac before treating as ironclad — the agent reported a stark divergence and it warrants a human eye.* |
| MED | `AppCore/AppBootstrapper.swift:28-51` | Five startup migrations (`fixCommunityTopicTagsIfNeeded`, `fixStudentLessonStudentIDsIfNeeded`, `migrateUUIDForeignKeysToStringsIfNeeded`, `migrateAttendanceRecordStudentIDToStringIfNeeded`, `migrateGroupTracksToDefaultBehaviorIfNeeded`) run synchronously on the main thread; large databases or first-time migrations can stall launch for many seconds. |
| MED | `Services/MigrationRegistry.swift:97-100` | Migrations v1 and v2 are listed as "already applied" with `print()` statements but no actual code path. Fresh installs whose `currentVersion` defaults to 0 will skip them silently. Likely benign (the work is presumably superseded), but the registry should explicitly mark them as no-ops or remove them. |
| MED | `Services/FollowUpWorkService.swift` | Type name appears only in its own file; no callers, no DI registration. Dead code or incomplete wiring. |
| MED | Codebase-wide | 60 instances of `try? …save()` and 264 of `try? …fetch()` outside the `safeFetch`/`safeSave` helpers. Per-feature batches flagged the worst; the rest is convention drift away from `Utils/ModelContext+SafeFetch.swift`. |
| LOW | `AppCore/CloudKitStatusSettingsView.swift:25-28` | `EnableCloudKitSync` toggle is read at startup only and requires app restart; UI surfaces this honestly ("Restart Required"). Documented but worth noting as a UX friction. |

---

## Known-issue verification

| Document | Status | Evidence |
|---|---|---|
| `CRITICAL_ISSUE_RAWCODABLE.md` | **FIXED** | No `@RawCodable` property wrapper exists. All affected models use the manual `*Raw: String` + computed enum pattern: `Models/WorkModel.swift:36`, `Models/Student.swift:28`, `Models/AttendanceModels.swift:82-83`, `Models/Note.swift:97`. Predicate sites (`WorksAgendaView`, `Services/DataQueryService`) reference the raw fields directly. |
| `PHASE_2_BLOCKED.md` | **FIXED** | `Utils/CloudKitUUID.swift` exists as a utility but is not applied to any `@Model`. All foreign keys on `Models/WorkModel.swift:48,50,52`, `Models/Student.swift:30`, `Models/AttendanceRecord.swift:79` are `String`. |
| `PHASE_3_INCIDENT_REPORT.md` | **FIXED** (with caveat) | `NoteCategory` has the documented 7 cases; the regressed domain-specific note types are gone. **Caveat:** `AppCore/AppSchema.swift:6-54` uses plain `Schema([...])` without `VersionedSchema`/`SchemaMigrationPlan`. The lesson the doc draws ("use VersionedSchema before any schema change") has not been adopted. `Services/SchemaMigrationService.swift` exists but is not wired into startup. This is forward risk, not a present bug. |
| `TECHNICAL_DEBT.md` (6 items) | All **STILL PRESENT**: (1) `Attendance/AttendanceEmail.swift:93` — `parseRecipients(_:)` defined-but-unused; (2) `Attendance/AttendanceEmail.swift:310` — TODO for `NSSharingServiceDelegate` timeout fallback; (3) `Services/BackupTelemetryService.swift:298` — `averageCompressionRatio: 0.0` hardcoded; (4) `Services/EnhancedBackupService.swift:235` — `conflicts: []` hardcoded, no detection logic; (5) `Lessons/LessonPickerComponents.swift:4` — refactor TODO; (6) `Tests/Performance/PerformanceBenchmarks.swift:2` — file disabled with `#if false`, references stale `WorkParticipantEntity` API. |

---

## Recommended next steps

In priority order (highest data-loss / functionality risk first):

1. **Replace the hardcoded backup password** at `Settings/SettingsViewModel.swift:95` with a user-supplied or keychain-stored secret. Until this is fixed, every "encrypted" backup is plaintext-equivalent.
2. **Add a pre-restore snapshot** in `Backup/BackupService.swift:255-259` and a `formatVersion` compatibility check at `:417`. Fail fast on unknown versions; preserve the existing DB if import fails.
3. **Wire the missing saves** in `Work/WorkStepRow.swift:58`, `Work/WorkStepEditorSheet.swift:67,79`. Either call the project's save coordinator after each service call or move the `save()` into the service methods themselves.
4. **Honor the work-completion contract.** Either invoke `WorkCompletionBackfill` from `Work/WorkDetailViewModel.swift:204` when status becomes `.complete`, or fold the record-creation directly into the transition. Update `lastTouchedAt` in the same path.
5. **Remove `nonisolated` from the three `WorkCheckIn` mutating methods** at `Work/WorkCheckIn.swift:95,102,109`, or move them to a service that takes the model and a context and does the mutation on the main actor.
6. **Audit `AppDependencies.makeTest()`** at `AppCore/AppDependencies.swift:346-356` against the production factory. Either align the schema and service registrations or document why the divergence is intentional. Re-run the test suite on a Mac after.
7. **Move startup migrations off the main thread** in `AppCore/AppBootstrapper.swift:28-51` once they've been confirmed safe to defer (some may have to run before the first view, but not all five).
8. **Add a recipient-required validator** in `Attendance/AttendanceEmail.swift:135` so the mail composer cannot present with an empty `to` list.
9. **Sweep `try?` on save/fetch** toward `safeSave`/`safeFetch` (see cross-cutting stats). Mechanical, but high signal in the long run.
10. **Confirm findings on a Mac.** Spot-check 5 HIGH items by opening the cited `file:line` in Xcode; run `xcodebuild test -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" -destination "platform=iOS Simulator,name=iPhone 15"` and look for new failures aligned with the work-step-save and work-completion-record findings — those are the most likely to surface in existing integration tests.

## What this report cannot tell you

- Whether any of the above bugs is masked or compensated for at runtime.
- Whether the test suite currently passes, fails, or is broken in some way unrelated to these findings.
- Whether SwiftUI previews render. Whether CloudKit sync works end-to-end. Whether backups actually round-trip on a real device.

These all require a Mac with Xcode. This report is a static-analysis baseline that points the human reviewer at the most suspicious code first.
