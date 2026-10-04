# Organization Audit: Cosmic Daybook (2026-10-02)

Base: `abc2b189` (main). Measured against the project's own rules in `docs/Technical notes/FEATURE_OWNERSHIP.md`. The previous pass was the 8-phase `../Plans/Plan - Repository organization.md` (closed 2026-07-10, now in `docs/Plans/`).

## Verdict

**Mostly organized.** The repo itself is tidy:
- The root has 11 entries.
- Documentation is filed into Architecture, ADRs, Implementation (with Archive) and Manuals.
- The Xcode project uses folder-synchronized groups.
- The tests mirror the source with a `Support/` folder.
- `Scripts/check_repository_structure.sh` passes.
- The rules in FEATURE_OWNERSHIP.md are good.

The problem is drift. 571 commits since the July reorganization have pushed feature code back into the shared layers that July had emptied:
- **Components/** has 75 loose files. 36 of them are used by only one feature. It also holds the whole 42-file class checklist, whose view model lives in `Lessons/Checklist/`.
- **Services/** has 54 loose files and **AppCore/** has 67, each in one flat list.
- **Models/** holds 36 entities while 40 others live in feature folders, so you can't guess where an entity is.

Several features also grew into flat folders of 40–65 files: Settings, Attendance, Daybook Assistant, Lessons, Today/Views and Albums.

Nothing found affects how the app behaves.

## Scorecard

| Area | Rating | Evidence |
|---|---|---|
| Folder structure (feature vs type, depth, crowding) | Needs work | 47 top-level folders under `Cosmic Daybook/` and mostly feature-shaped. But type buckets regrew: Components 131 files (75 loose), Services 159 (54 loose), Utils 66 (all flat), Models 55, AppCore 84 (67 loose). 24 folders have 20+ files directly inside. Five folders hold 1–2 files: Inbox, Progression, Community, Agenda, ClassroomJobs. |
| File size and focus | OK | 41 app files over 400 lines; only one is near 1,000 (`Albums/AlbumDetailView.swift`, 975). Most long files are cohesive (AutoBackupManager, QuickNoteSheet, CoreDataStack+OrphanCleanup, SequenceRecapBlocks). Real splits: AlbumDetailView, ThisWeeksParshaView, RootView, DataManagementGrid, AlbumLibrary, and one grab bag (`Work/Detail/WorkDetailViewComponents.swift`, 13 types). |
| Naming | Good | Consistent `FooEntity.swift` → `CDFoo`, `Type+Capability.swift`, and `*View`/`*ViewModel`/`*Service` suffixes. A handful of misleading names: `ClassSubjectChecklistView.swift` declares `ClassAreaChecklistView`; `Models/Note.swift` holds only `NoteCategory`/`NoteScope`; `Models/Presentation.swift` holds `LessonAssignmentState`; `Services/MCPClient.swift` is the language-model client, not MCP. |
| Tests layout | Good | 26 of 27 test folders match a source folder, plus `Support/`. `Tests/Services/Sync/` (19 files) is a better grouping than the source has. 20 small source features have no tests folder, which reflects missing tests rather than layout. |
| Resources and config | Good | Info plists, entitlements and privacy manifests sit with their targets. `.swiftlint.yml`, `.swift-format.json`, CLAUDE.md and README are excluded from the bundle through a membership exception. The `Icon-1024 1.png`-style files are referenced by `Contents.json` (Xcode's per-slot copies), so they aren't junk. |
| Root and hygiene | Good | No junk, no secrets, no xcuserdata, no large binaries, no empty folders. There are two comment-only placeholder files and one dead file (see Quick wins). |

## Top suggestions

### 1. Give the class checklist and the command bar one home each

**What's wrong:**
- The class checklist is split three ways:
  - Views: `Components/Checklist/`, 42 files, plus `Components/ClassSubjectChecklistView.swift`.
  - View model: `Lessons/Checklist/ViewModels/`, 9 files.
  - Tests: `Tests/Planning/Checklist*`, plus one in `Tests/Components`.
  - It is a feature, not a component. Its only outside consumers are the route in `AppCore/RootView/RootDetailContent.swift:105`, `ChecklistMark` (Students/Progress) and `ShowInChecklistButton` (Lessons, Presentations, Work).
- The command bar is split across `Components/CommandBar/` (2), `Services/CommandBar/` (6) and `ViewModels/` (3 files, which is that whole folder).

**Why it matters:** the checklist is under active redesign, and anyone opening it finds half of it. "Where's the checklist?" currently has three answers, and CLAUDE.md gives a fourth ("Planning/ — Planning & checklist tools").

**Proposed change:**
- **Checklist, option A (recommended):** move it to `Lessons/Checklist/Views/`, next to its view model, and rename `ClassSubjectChecklistView.swift` → `ClassAreaChecklistView.swift` (its own header already uses that name).
- **Checklist, option B:** move both views and view model to `Planning/Checklist/`, to match CLAUDE.md. Your call.
- **Command bar:** create a top-level `CommandBar/` with `Views/` (CommandBarSheet, CaptureProposalReviewView), `ViewModels/` (3) and `Services/` (6). Then delete the empty `ViewModels/`.

**Knock-on edits:**
- CLAUDE.md Project Structure (drop `ViewModels/`, fix the checklist line).
- `docs/Plans/Plan - Class checklist redesign.md`, `DeveloperManual.md`, `.claude/skills/efficiency-pass/references/codebase-map.md`.
- Move `Tests/Components/ChecklistMatrixBuilderEquivalenceTests` to match.
- Nothing here is compiled into the Assistant by path.

**Effort / risk:** S / low. Pure `git mv` in synchronized folders.

### 2. Send single-feature files out of Components/

**What's wrong:** 36 of the 75 loose files in `Components/` have one consumer feature. FEATURE_OWNERSHIP says they move to that feature:
- 10 `*WindowHost.swift` files, each referenced only from `AppCore/CosmicDaybookApp.swift`'s scene list and each showing one feature's record. The precedent is `Students/Meetings/MeetingSessionWindowHost.swift`.
- 9 Students-only files: StudentSharedComponents, ReportGeneratorView, AppleIntelligenceSheet ×2, NextLessonsSection, ProgressionLessonRow, DaysSinceLastLessonView, InfoRowView, ParsingOverlay.
- 5 Work-only files: OpenWorkGrid ×2, SubjectGrainPill ×2, PaginatedList.
- 3 CurriculumMap-only files: StickyLeft* ×3.
- 2 Presentations-only files: InboxOrderStore, WorkspaceDeletionConfirmation.
- 2 for AppCore: SyncingFromICloudOverlay, OpenWindowOnNotificationModifier.
- The rest: LessonJourneyTimeline → Lessons, DayHalfPicker → Inbox, WindowOcclusionProbe → Utils.

**Why it matters:** `Components/` is supposed to answer "what can I reuse?". Today it holds 75 files, and half of them only one screen can use.

**Proposed change:**
- Move each file to its consumer (full table in the inspector notes below).
- `EntityWindowHost` (the shared shell for the hosts) moves to a new `AppCore/Windows/`.
- Group the six WaitingStudent* files and StudentWaitVocabulary into `Components/WaitingStudents/`.
- Result: about 32 loose files, all genuinely shared.

**Knock-on edits:** CLAUDE.md and DeveloperManual paths, `codebase-map.md`. None of these files is compiled into the Assistant.

**Effort / risk:** S–M / low.

### 3. Put each entity with its feature (Models/)

**What's wrong:**
- `Models/` holds 36 `*Entity.swift` files, while 40 others already live in feature folders (Work 7, Projects 6, Students 5, Attendance 4, BookClub 3…).
- About 33 of the 51 Models files have a single owning feature. Examples:
  - Todo* (5) while `Todos/` exists.
  - Procedure* (2) while `Procedures/` exists.
  - Supply* (3) while `Supplies/` exists.
  - Schedule*/ScheduleSlot while `Schedules/` exists.
  - Community*/ProposedSolution/Issue* → `Topics/`.
  - ParentCommunication + CommunicationType → `ParentReports/`.
  - TodayAgendaOrder → `Today/Support/`.
  - PlanningRecommendation → `Planning/`.
  - DevelopmentSnapshot → `Students/Insights/`.
- Nothing about Core Data forces them to be central. There is no codegen, and stores are routed by configuration name, not by file path.

**Why it matters:** right now the only way to find `CDTodoItem` is to search. Under the stated rule you'd look in `Todos/` first and be right.

**Proposed change:**
- Move the single-feature entities.
- Keep the ~18 cross-feature ones in `Models/`: Note*, LessonAssignment, LessonPresentation*, Presentation*, LessonRecallCheck, Document, YearPlanEntry, Reminder, NonSchoolDay, SchoolDayOverride, CoreDataIdentifiable, ModelExtensions, CDUnifiedNotes+Helpers, TodoTag.
- In the same pass, fix the misleading names:
  - `Note.swift` → `NoteCategory.swift`
  - `Presentation.swift` → `LessonAssignmentState.swift`
  - `LessonPresentation.swift` (8 lines) → `LessonPresentationState.swift`
  - Fold the 7-line `UnifiedNotes+Helpers.swift` into `CDUnifiedNotes+Helpers.swift`. That one edits code, so keep it out of the move commit.

**Knock-on edits:**
- 3 Models files are compiled into the Assistant by path: DocumentEntity, NonSchoolDayEntity, SchoolDayOverrideEntity. All three stay put.
- Docs: `DATA_MODELS.md`, CLAUDE.md "Data Model".

**Effort / risk:** M / low. One commit per destination feature.

### 4. Sort Services/ and AppCore/ into subfolders, and move out the feature-owned pieces

**What's wrong:** `Services/` has 54 loose files and `AppCore/` has 67. Some of these files belong to one feature:
- `PresentationRecordIndex` ×4 → `Presentations/Index/`
- `ReportGeneratorService` (680 lines) + `AIReportService` → `ParentReports/`
- `ImportCommitService` → `Students/Import/`
- `MCPClient`/`MCPTypes` and `AppCore/AIPrompts` → `Services/AI/` (they are the language-model client and prompts)
- `DataMigrations`/`MigrationRunner` → the existing `Services/Migrations/`
- `SharedStoreOrphanGuard` → `Sharing/`
- `RootView.swift` + `RootView+*.swift` ×3 sit beside the `AppCore/RootView/` folder rather than in it.

**Why it matters:**
- Sync code is the most delicate in the app, and it is spread through a 54-file list rather than gathered in one place. The tests already group it (`Tests/Services/Sync/`, 19 files); the source doesn't.
- `AppCore/` mixes persistence bootstrap (CoreDataStack ×7), window plumbing, theme and the sample-classroom seeder with the app entry point.

**Proposed change:**
- **Services:**
  - `Sync/` (18): CloudKitSyncStatusService ×5, CloudKit checks ×3, PersistentHistoryProcessor ×2, DeduplicationCoordinator, SyncEventLogger, SyncRetryLogic, SyncStoppedAdvice, FirstDownloadGate, UnsentChangesKeepAlive, UbiquitousDownloadSweep
  - `Search/` (3)
  - `Calendar/` (6): EventKit, Reminder and CalendarSync
  - `Photos/` (2)
  - `System/` (4)
  - `Progression/` (6): the recorded shared exception, kept shared
  - `Toast/` (ToastService + ToastOverlayModifier, with ToastBanner from Components)
- **AppCore:** `Persistence/` (CoreDataStack ×7, DatabaseError ×3, CloudKit config ×3), `Windows/` (7 + EntityWindowHost), `SampleClassroom/` (3), `Theme/` (4), with RootView files into `RootView/`. About 22 composition files stay at the root.

**Knock-on edits:**
- **The big one:** 19 of these files are compiled into the Daybook Assistant by explicit path (`sourceTree = SOURCE_ROOT` in the pbxproj): CoreDataStack ×7, CloudKitConfigurationService, CloudKitEnvironment, AppCalendar, ShareAcceptanceAppDelegate, FirstDownloadGate, PersistentHistoryProcessor ×2, UnsentChangesKeepAlive, Notification.Name+PresentationData/SchoolDayData. Each move needs its `path =` updated in `project.pbxproj`, and the Assistant build confirms it.
- CLAUDE.md, ARCHITECTURE.md, `codebase-map.md`, DeveloperManual.

**Effort / risk:** M / medium. Do it in two commits: (a) the feature-owned files out and (b) the subfolders.

### 5. Split the flat Utils/ folder

**What's wrong:** 66 files sit in one flat folder. 14 of them belong to a feature:
- CSV* ×4 → `Students/Import/` (only the student CSV importer uses them)
- StudentFormatter, StudentSortComparator, AgeUtils → `Students/`
- FloridaGradeCalculator → `SchoolYear/`
- BackupCountHelpers → `Backup/`
- MarkdownExporter → `Topics/`
- PrintUtils → `Albums/`
- LessonFormatter → `Lessons/`
- `SyncedPreferencesStore` (472 lines) is a store, not a utility → `Services/`

**Why it matters:** a 66-file flat list of extensions and helpers is where duplicates get written because nobody finds the existing one.

**Proposed change:** the remaining ~52 go into `Extensions/`, `Formatting/`, `SwiftUI/` (the nine `View+*` files), `Visibility/`, `Files/`, `CoreData/`, `Platform/` and `Diagnostics/`, each under 12 files.

**Knock-on edits:** 6 Utils files are compiled into the Assistant by path: AppErrorMessages, AppLogging, LaunchSignposts, Logger+Extensions, NSManagedObjectContext+SafeFetch, String+Extensions. Each needs its pbxproj path updated.

**Effort / risk:** S–M / low.

### 6. Give the flat feature folders domain subfolders

**What's wrong:** these folders have 39–65 files directly inside:
- Settings 65
- Daybook Assistant 58
- Attendance 55
- Lessons 44
- Today/Views 43
- Albums 40
- Students/Meetings 39

**Why it matters:** these are the folders that change most. Scanning 55 `Attendance*` names to find the email code costs time every time.

**Proposed change:** use the file-name families, which already split cleanly:
- **Settings:** `Classroom/`, `Sync/`, `DataManagement/`, `Templates/`, `Dashboard/`, `Shell/`
- **Attendance:** `Email/` (7), `Store/` (~14), `Views/` (~16), `Reports/` (~8). Move the InsightsService files into the existing `Insights/`.
- **Daybook Assistant:** `Attendance/`, `Onboarding/`, `Siri/`, `Reminders/`, `Sync/`, `FrontDesk/`, `Wallpaper/`. Info.plist and entitlements stay where they are.
- **Today/Views:** `Attendance/`, `Sections/`, `Rows/`, `Shell/`
- **Lessons:** `Attachments/`, `Detail/`, `ScopeMap/`, `Root/`
- **Albums:** `Library/`, `Search/`, `Detail/`, `Lessons/`, `Browse/`
- **Students/Meetings:** `Session/`, `Workflow/`, `Tab/`, `Data/`

**Knock-on edits:**
- 37 Attendance files are compiled into the Assistant by path, so the Attendance regroup is mostly pbxproj path edits. Do it last, alone.
- Extend `check_repository_structure.sh`'s loose-file rule to these folders, or they will flatten again.

**Effort / risk:** M overall / low. Attendance is medium because of the pbxproj.

### 7. Split the handful of long files that hide separate pieces

**What's wrong:**
- `Albums/AlbumDetailView.swift` (975 lines, 11 commits since Aug 1) is a 668-line view with four unrelated views stacked below it.
- Moderate cases:
  - `Parsha/ThisWeeksParshaView.swift` (600; seven types)
  - `AppCore/RootView.swift` (531; 18 commits since Aug 1, the most-edited)
  - `Settings/DataManagementGrid.swift` (663; five independent cards)
  - `Albums/AlbumLibrary.swift` (653; the `Album` model plus the library)
  - `Work/Detail/WorkDetailViewComponents.swift` (13 unrelated types)

**Why it matters:** the album view's panels can't be found by name, and every edit to one recompiles and re-reviews all of them.

**Proposed change:**
- AlbumDetailView: move `RelatedLessonsPanel`, `AlbumOutlineListView`, `AlbumPageNotesPanel` and `AlbumSummarySheet` to their own files. Optionally add `AlbumDetailView+Toolbars.swift`, following the existing +Ink/+Sheets pattern.
- ThisWeeksParshaView: move the rows to `ParshaRows.swift`.
- RootView: add `RootView+Chrome.swift` and `RootView+Selection.swift`.
- DataManagementGrid: create `Settings/DataManagement/` with one file per card.
- AlbumLibrary: create `Album.swift` and `AlbumLibrary+TextIndex.swift`.
- WorkDetailViewComponents: split into `PracticeStats`, `WorkDetailButtons`, `WorkDetailCards`, `WorkDetailMetrics` and `NoteRowView`.
- Leave AutoBackupManager, CoreDataStack+OrphanCleanup, QuickNoteSheet, SequenceRecapBlocks and AssistantAttendanceView alone. Each is cohesive.

**Knock-on edits:** none outside the files. Splits widen some `private` members to internal.

**Effort / risk:**
- S each / low: AlbumDetailView panels, Parsha rows, WorkDetail.
- Medium: RootView and AlbumLibrary (shared private state, concurrency).
- These suit `refactor-standard` agents in parallel, since synchronized folders mean no pbxproj edits.

## Quick wins

- **Refresh CLAUDE.md's Project Structure map.**
  - It omits 12 of the 47 top-level folders: BookClub, Chat, ClassroomJobs, ObservationMode, ParentReports, Parsha, ProgressDashboard, Schedules, SchoolYear, Siri, SmallSequencePlanner, Stories.
  - It still says the checklist lives in Planning.
  - The next session trusts this map.
- **Delete `Components/SidebarFilterButton.swift`.** Nothing references `SidebarFilterButton` or `FilterButton` anywhere in the repo, so it is confirmed dead. It needs your OK.
- **Delete the two placeholder files.**
  - `Today/Views/TodayViewSections.swift` and `Work/Models/WorkParticipant.swift` are comment-only.
  - The stated reason ("avoid file-not-found references") doesn't apply under synchronized folders.
  - Also fix the stale comment at `Today/Views/TodayView.swift:7`.
  - Needs your OK.
- **Rename `Components/ClassSubjectChecklistView.swift` → `ClassAreaChecklistView.swift`.** Do it as part of #1.
- **Move the generic `Center<Content>`** out of `Notes/QuickCapture/QuickNoteComponents.swift`. Students and Utils use it, so it belongs in `Components/`.
- **Settle the three "progress" homes** (`Progression/`, 1 file; `ProgressDashboard/`, 8; `Students/Progress/`) and the other one-file folders:
  - `Inbox/` (1): fold into Presentations? It is "the inbox-status section of the presentation detail".
  - `Community/` (1): fold into Topics, where its entities belong.
  - `Agenda/` (2)
  - This is a question for you rather than a move list.
- **Consider trimming `Cosmic Daybook/CLAUDE.md`.**
  - It is 90 KB (379 very long lines) and every session reads it first.
  - Feature histories such as the attendance, Siri and orders notes could move to `docs/Technical notes` with a one-line pointer each.
- **Mirror the source regroup in tests afterwards.** `Tests/Services/` has 11 loose files: SearchIndex* ×4 → `Search/`, PresentationRecordIndex* ×3 → `Presentations/`.

## Found along the way

- Nothing that changes how the app behaves.
- One fact to know before any move: **88 app files are compiled into the Daybook Assistant by explicit path**:

| Folder | Files |
|---|---|
| Attendance | 37 |
| AppCore | 13 |
| Siri | 8 |
| Sharing | 8 |
| Utils | 6 |
| Services | 6 |
| Students | 3 |
| Models | 3 |
| Work | 2 |
| Repositories | 1 |
| Backup | 1 |

- That is deliberate ("shared by path, one seam" in CLAUDE.md), so it stays.
- It means a `git mv` of any of those files leaves the Assistant target with a missing file until `project.pbxproj` is edited. Build the Assistant scheme after every move commit.
- A longer-term option is to gather the 88 into one shared folder, or a local package. That would make the seam visible, but it is a design decision, not a tidy-up.

## Already well organized

Leave these as they are:
- **Root:** 11 entries and nothing stray.
- **Documentation/:** Architecture, ADRs, Implementation (with dated perf-baselines and an Archive), Manuals and Generated.
- **Scripts/:** one folder, with build lock, install, archive and Periphery scripts.
- **Backup/:** well subfoldered (Core, Archive, Export…), and the 35-spec `ModelRowKinds.swift` and `BackupTypes+*.swift` DTO files are deliberate collection files.
- **Students/:** 183 files, all in domain subfolders. This is the model the flat folders should copy.
- **Services/MCPServer/:** 72 files in one consistent `MCPNotebookTools+Topic.swift` family that's easy to scan by name.
- **Tests:** they mirror the source, have shared fixtures in `Support/`, and group Sync tests better than the source does.
- `Tests/Backup/BackupService+LegacyRestore.swift` (1,098 lines) is a deliberate frozen copy of the old restore, used by the equivalence and peak-memory tests. Don't "fix" it.
- **Ownership rules and the structure check:** FEATURE_OWNERSHIP.md plus `check_repository_structure.sh` are exactly the right tools. The check just needs a wider net (see #6).
- **Naming conventions** are consistent: `FooEntity.swift` → `CDFoo`, `Type+Capability.swift`, `Notification.Name+X.swift`.

## Since the last audit

The last pass was `../Plans/Plan - Repository organization.md`, phases 0–8, closed 2026-07-10. There have been 571 commits since.

**What held:**
- No tracked user data.
- Backup consolidated.
- Today co-located.
- No loose files at the roots of Students, Work, Presentations or the test target.
- Tests mirrored.
- The structure check passes.

**What drifted:**
- **Components:** Phase 4 extracted feature code from it. It now holds 36 single-feature files again, plus the 42-file checklist that arrived with the redesign.
- **Services:** Phase 5 moved 37 feature files out. It now has 54 loose files, including PresentationRecordIndex, ReportGeneratorService and ImportCommitService.
- **New feature folders:** twelve new top-level folders appeared without a CLAUDE.md map update.
- **Flat folders:** Settings, Attendance, Lessons and Albums grew flat past 40 files. The structure check only guards Students, Work and Presentations.

**New since July:**
- The Daybook Assistant target and its 88 by-path shared files.
- The Albums, Orders, CurriculumMap and ParentReports features.

---

### Inspector notes (verification detail)

- **Scan false positives:**
  - All five "type mentioned by no other file" leads are live. They are reached through View-extension modifiers: `.adaptiveAnimation`, `.stickyLeftScrollTracking()`, `.syncingFromICloudOverlay()`, `.toastBanner`, `.workspaceDeletionConfirmation`, and `.toastOverlay` for ToastOverlayModifier.
  - The scan missed the one truly dead file, `SidebarFilterButton.swift`.
- **`CDMeetingTemplate` is live.** It is used by MeetingTemplateRepository, BuiltInTemplateSeeder and the MCP planning tools.
- **Components → feature destinations:**
  - AlbumWindowHost → Albums
  - CommunityTopicWindowHost → Community/Topics
  - LessonDetailWindowHost → Lessons
  - NoteEditorWindowHost → Notes
  - PresentationDetailWindowHost → Presentations
  - ResourceDetailWindowHost → Resources
  - Student{Detail,Documents,Report}WindowHost → Students
  - WorkDetailWindowHost → Work
  - AppleIntelligenceSheet ×2 → Students/Notes
  - ReportGeneratorView → Students/Reports
  - StudentSharedComponents → Students/Shared
  - NextLessonsSection, ProgressionLessonRow → Students/Progress
  - DaysSinceLastLessonView, InfoRowView → Students
  - ParsingOverlay → Students/Roster
  - LessonJourneyTimeline → Lessons
  - OpenWorkGrid ×2, SubjectGrainPill ×2, PaginatedList → Work
  - InboxOrderStore, WorkspaceDeletionConfirmation → Presentations
  - DayHalfPicker → Inbox
  - StickyLeftItem, StickyLeftScrollTracking, EnvironmentValues+StickyLeftOffset → CurriculumMap
  - SyncingFromICloudOverlay, OpenWindowOnNotificationModifier → AppCore
  - WindowOcclusionProbe → Utils

---

## Applied (2026-10-02)

All seven suggestions and the quick wins landed as separate move-only commits, with the checklist placed under `Lessons/Checklist/` (option A).

**Deviations from the plan:**
- **Ambiguous owners left in place**, per FEATURE_OWNERSHIP's "if ownership is ambiguous, leave it" rule:
  - SchoolCalendarService, AppCalendar and BuiltInTemplateSeeder.
  - The track, issue, meeting-template, note-template, DayPad and calendar-event entities.
  - `Theme` went to `AppCore/Theme/` rather than Components.
- **Skipped splits**, because each would have widened too many `private` members to be worth it:
  - `RootView+Selection.swift`: about 14 members.
  - `AlbumDetailView+Toolbars.swift`: about 19 members.
- **`ParshaLessonRow` stayed private** in `ThisWeeksParshaView.swift`. `Lessons/Parsha/ParshaLessonListView.swift` has its own private type with the same name.
- **The checklist split into `Views/` (22) and `Model/` (21)**, so that no folder exceeds the new 40-file limit.
- **Not done:** CLAUDE.md is not trimmed, and the one-file folders (Inbox, Community, Progression, Agenda) are untouched. Both still wait on Danny.

**Verification:**

| Check | Result |
|---|---|
| macOS, iOS and Daybook Assistant builds | Succeeded. The only warnings are the two existing type-check timings in `QuickNoteGlassButton.swift` |
| Full app suite, iOS Simulator | 481 passed, 6 failed (see below) |
| Rerun of the 6 failures | All passed, 0.4 s each against 43–60 s the first time |
| Assistant suite | 142 passed |
| `check_repository_structure.sh` | Passes |

The 6 first-run failures were timeouts on one busy simulator clone, not real failures.
