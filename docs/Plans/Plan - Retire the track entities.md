# Retire the track entities

> **Working on it.** Phases 1 and 2 done 2026-11-04; Phase 3 is built on branch `claude/track-phase3-drop-schema` and waits for roll-out A on every device. Written 2026-11-03 after a look at the two generations, before any new schema work (session on branch `claude/track-schema-generations-b064c1`).
> In short: Track, TrackStep, SequenceTrack and StudentTrackEnrollment are an older, stored copy of what the lesson sequences, the Year Plan and LessonSequenceSettings now carry; stop writing them, show the same cards from the presentation record, then drop the four entities and the trackID columns.

## Why

Danny noticed that the four track entities and the pair YearPlanEntry + LessonSequenceSettings read like two generations of the same idea, and asked for a look before adding to the schema. The look confirmed it. The older generation (ported from SwiftData on 2026-03-30) stores as rows what the newer one (2026-04-06 and 2026-05-17) derives, and only three screens and one MCP tool still read it.

What the four entities are today:

- **Track is keyed by a string.** `SequenceTrackService.getOrCreateTrack` finds a track by the title `"Area — Sequence"`, and `StudentTrackDetailLoader` splits that title on the em dash to get the area and sequence back. Titles defined twice needed their own launch-time merge (`DataCleanupService+TrackTitleMerge`, 2026-09).
- **TrackStep is a cache of the sequence.** `cdEnsureTrackSteps` rebuilds the steps from `Lesson.orderInSequence` on every lookup. `TrackProgressResolver` matches a presentation by lesson ID *or* step ID, so the step ID decides nothing. `StudentTrackDetailView` does not read steps at all; its `StudentSubjectProgressionViewModel` reads the lessons.
- **StudentTrackEnrollment is derived state stored as rows.** Seven call sites enroll a child the moment any lesson of a sequence is given (`autoEnrollInTrackIfNeeded`), and `checkAndCompleteTrackIfNeeded` closes the enrollment once every lesson is mastered. That is exactly what the Year Plan stopped doing: there, "satisfied" is read off the presentation record (`YearPlanSatisfaction`), never stored.
- **SequenceTrack and LessonSequenceSettings are twins.** Both are one row per (area, sequence), both found by a case-insensitive string match, both written by the one Save button of `SequenceTrackSettingsSheet`. `isSequential` is read by nothing but that sheet and the title merge. `isExplicitlyDisabled` ("Use as Track") only stops auto-enrollment and the trackID stamps.
- **Three heavy tables carry the stamps.** `trackID` and `trackStepID` sit on LessonPresentation, LessonAssignment and WorkModel; `studentTrackEnrollmentID` on Note. Every one is derivable from the row's lesson.

A live sample on 2026-11-03 showed what the cards say: every track of the two children checked stood at 0 of N mastered, so a card tells her "she has had a lesson here" and "the next lesson", which the Checklist and the Year Plan already derive (d018c364, 8c830a65).

None of the four entities is in the classroom share (they left it at schema 9), so the Daybook Assistant never sees them and no share release is involved.

## Who reads the older generation

- **Current Learning** (`Students/Progress/StudentProgressTab.swift`, `StudentProgressTabViewModel.swift`): one card per active enrollment with mastered/total, the next lesson, presentation/work/note counts filtered by `trackID`, the latest note on the enrollment, and a link to the class view. Its sheets: `StudentTrackDetailView` (+ `StudentTrackDetailLoader`) and `TrackFilteredListView` (+ `TrackFilteredListLoader`).
- **Past Learning** (`Students/Detail/StudentHistoryTab.swift`): finished enrollments, folded by title.
- **MCP `student_tracks`** (`Services/MCPServer/MCPNotebookTools+Reference.swift`): the same numbers for a chat.
- **Writers**: `Services/Progression/SequenceTrackService.swift` (+ `ScopedReads`), called from `Lessons/Checklist/ViewModels/ClassSubjectChecklistViewModel+CellActions.swift`, `Lessons/Checklist/Model/ChecklistBatchActionExecutor.swift`, `Students/Presentations/PresentationDetailViewModel.swift`, `Presentations/Workflow/ImmediatePresentationRecordingService.swift` (+ `Snapshots`, `UndoSupport`), `Work/Services/LifecycleService+PresentationRecording.swift`, `Work/Support/WorkRepository.swift`, `Lessons/AddLessonView.swift`, `Lessons/BulkLessonInsertion.swift`, `Services/MCPServer/MCPNotebookTools+CurriculumSupport.swift`.
- **Housekeeping**: `DataCleanupService+TrackTitleMerge.swift`, `NotebookJunkCleanup.swift` (`emptyTracks`, `trackLessEnrollments`), `DataCleanupService+LessonNameMerge.swift` (`repointTrackSteps`), `DataCleanupService+DeduplicateLessons.swift` and `+DeduplicateWork.swift` (trackID lines), `Students/Services/StudentDeletion.swift`, `Settings/Dashboard/SettingsStatsViewModel.swift` (the Tracks and Track enrollments rows), `Backup/BackupEntityTable.swift`, `Backup/Import/BackupEntityImporter+Tracks.swift`, `Backup/ModelRowKinds.swift`, `Backup/BackupTypes*.swift`.
- **Tests**: 19 files name the entities or the service, among them `Services/Progression/SequenceTrackServiceScopeTests`, `Services/TrackTitleMergeTests`, `Services/MCPServer/MCPStudentTracksToolTests`, `Students/Progress/StudentTrackDetailLoadScopeTests` and `StudentProgressTabLoadScopeTests`, `Work/PresentationRecordingScopedReadsTests`, `AppCore/ClassroomShareShrinkMigrationTests`, and the backup fixture and coverage tests.

Size: about 4,100 lines in the generation's own files, before the call sites.

## Decisions

- **Retire, don't extend.** Until this plan lands, no new field goes on the four entities. A new per-sequence setting goes on `LessonSequenceSettings`.
- **The cards stay, derived.** Current Learning keeps a card per sequence the child is in the middle of; the numbers come from the presentation record, not from rows. Why: the cards are the one place the app shows "where she stands in this strand" at a glance, and the Year Plan tab shows dates, not standing.
- **A "sequence standing" is computed, not stored.** For one child and one (area, sequence): the lessons in order, which are given, which are mastered (a mastery mark: `masteredAt` set or state proficient, the rule `TrackProgressResolver` and `CurriculumMapLoader` share since c40fa961), and the lesson she is up to (the first not yet given, d018c364's rule). "In the middle of" means at least one presentation and not every lesson mastered; "finished" means every lesson mastered. This is what an enrollment and its steps were trying to be.
- **"Use as Track" goes.** It only switched auto-enrollment off; with no enrollments there is nothing for it to switch. The Track Settings sheet keeps its second section (the progression rules on `LessonSequenceSettings`) and loses the first, and is renamed for what is left. See the first open question before building this.
- **`isSequential` goes** with its entity. Nothing read it.
- **The filters move to the lesson.** "Presentations / work / notes on this track" become "on a lesson of this sequence": predicates on `lessonID IN` the sequence's lesson IDs, which `SequenceTrackService+ScopedReads.sequenceLessons` already computes. The `trackID` and `trackStepID` columns then have no reader.
- **Notes on an enrollment become notes on the child.** A one-time launch step copies the enrollment's `studentID` onto any note whose `studentTrackEnrollmentID` names it (where the note's own student is empty) and the column goes. See the second open question for whether a sequence name should be kept on the note.
- **`student_tracks` keeps its name** and answers from the sequence standing, so Cowork chats that call it keep working. `docs/Technical notes/MCP_SERVER.md` row updated.
- **Two roll-outs, not one.** Roll-out A ships phases 1 and 2 (nothing writes the old rows; the new cards read nothing from them). Roll-out B, after every device runs A, ships phase 3 (the entities and columns leave the model). Why: a device still on the old build would keep writing records of types the new model no longer has.
- **Model edited in place**, as the repo does (one model version; removing entities and attributes is a lightweight migration), with `currentSchemaVersion` bumped from 22 and `BackupWriter.formatVersion` from 44.
- **Old backups still restore.** The four tables are `.optional` collectors; once removed, an old backup's track arrays are simply not decoded. The coverage and fixture tests say so.

## Ruled out

- **Making the newer generation own the tracks** (giving `LessonSequenceSettings` steps and enrollments). It would re-create the cache under a new name; the sequence's lessons are the steps.
- **Keeping enrollments as a "started this strand" record.** The first presentation in the sequence is that record, with a date.
- **Keeping `trackStepID` as a faster join.** Every reader already falls back to `lessonID`, and the Checklist's per-child reads (`StudentChecklistState`) manage without it.
- **A migration that converts enrollments into Year Plan entries.** An enrollment is not an intention; it says a lesson was given, which the presentation already says.

## Phases

### Phase 1 — Stop writing (roll-out A)

- Remove every `autoEnrollInTrackIfNeeded` and `checkAndCompleteTrackIfNeeded` call (the seven call sites above) and the `trackID`/`trackStepID` stamping in `LifecycleService+PresentationRecording`, `WorkRepository.linkWorkToTrack`, `ImmediatePresentationRecordingSnapshots`, `PresentationGroupMove`, `PresentationSplitService`; the undo snapshots of created enrollments in `ImmediatePresentationRecordingService` go with them.
- `AddLessonView`, `BulkLessonInsertion` and the MCP `create_lesson` path stop calling `getOrCreateTrack`.
- The Track Settings sheet loses "Use as Track" and the track type; it saves `LessonSequenceSettings` only.
- Quick notes can no longer attach to an enrollment (`Notes/QuickCapture/QuickNoteViewModel+Saving.swift`, `CDUnifiedNotes+Helpers`).
- The launch merge `mergeSameTitleTracks` and the junk-cleanup lines `emptyTracks` / `trackLessEnrollments` stay until phase 3, when the entities they tidy go too: retiring them earlier would have meant touching the dedup and cleanup tests twice for rows that are deleted wholesale a roll-out later. (Decided while building, 2026-11-03.)
- The `mark_mastered` batch no longer saves part-way: finishing a track was the one inner save, so the "these were kept" reply and `noticingSaves` go with it.
- Tests: the scoped-read and recording tests that pinned the writers go; the MCP mastery tests seed their track by hand (`CoreDataTestHelpers.seedTrack`).

### Phase 2 — Derived cards (roll-out A)

- New `Students/Progress/SequenceStanding.swift`: the value above, computed by a loader scoped to one child (the pattern of `StudentTrackDetailLoader` and `StudentSubjectProgressionViewModel.configure(for:area:sequence:)`, whose fetches it reuses).
- `StudentProgressTabViewModel` lists the child's in-progress standings instead of enrollments; the card, the detail sheet and the filter sheets take `(student, area, sequence)` instead of `(enrollment, track)`. The next-lesson banner, counts and class link keep their look.
- `StudentHistoryTab` lists finished standings instead of finished enrollments.
- `student_tracks` reads standings; same wording in its reply.
- Settings › the stats dashboard drops the Tracks and Track enrollments rows.
- Tests: `StudentProgressTabLoadScopeTests` and `StudentTrackDetailLoadScopeTests` keep their registered-objects counts against the new loaders; `MCPStudentTracksToolTests` seeds presentations instead of enrollments; a new `SequenceStandingTests` covers in-progress, finished, the up-to rule and a sequence with no presentations.
- Both phases: build the app, run `-only-testing:` for Students/Progress, Services/Progression, Services/MCPServer, Work and Presentations, then the whole suite once; roll out.

### Phase 3 — Drop the schema (roll-out B)

- Delete the entities Track, TrackStep, SequenceTrack, StudentTrackEnrollment from the model and their four `Models/*Entity.swift` files; delete `trackID` and `trackStepID` from LessonPresentation, LessonAssignment and WorkModel, and `studentTrackEnrollmentID` from Note, after the one-time note step above has run on launch.
- `CoreDataStack+Model.privateEntityNames` and `CoreDataStack+SchemaVersion` lose the names; `currentSchemaVersion` bumps.
- Backup: the four collectors leave `BackupEntityTable`, with `BackupEntityImporter+Tracks`, the DTOs in `ModelRowKinds` and `BackupTypes`, and `BackupPlainNames`; `formatVersion` bumps. `BackupFieldCoverageTests`, `BackupSparseRowTests`, `BackupRestoreFixtures` and the legacy collector/restore helpers drop the rows; a restore of a pre-change fixture that still holds track arrays must pass.
- `SequenceTrackService`, `TrackProgressResolver`, `DataCleanupService+TrackTitleMerge`, `StepProtocol` and the track lines in deduplication and `StudentDeletion` go. `DATA_MODELS.md`, `BACKUP_SYSTEM.md`, `MCP_SERVER.md`, `CLOUDKIT_GUIDE.md` and the School year separation plan's evergreen table lose their mentions.
- Confirm in Settings that the CloudKit record types staying in Production do no harm (they are ignored; nothing to deploy).
- Build, whole suite, roll out.

## Open questions for Danny

1. **Did you ever switch "Use as Track" off for a sequence?** If yes, what were you after: hiding it from Current Learning, or something else? That decides whether a "don't show as a strand" flag moves to `LessonSequenceSettings` or the switch just goes.
2. **Do you write notes on a track card?** If so, should the note keep the sequence's name (a `sequenceKey` on Note), or is a note on the child enough?
3. **Should Current Learning keep one card per strand, or shrink to the next lessons only?** The plan keeps the cards, smaller.

Answered 2026-11-04 by Danny approving the plan's defaults without changes: (1) the switch just goes, no hide flag; (2) a note stays on the child, no `sequenceKey`; (3) Current Learning keeps one card per sequence, built from the presentation record.

Not checked from here: how many enrollments and enrollment-linked notes the live store holds (the container is TCC-blocked); the stats dashboard in Settings shows both counts.

## Progress

- [x] Phase 1 — Stop writing (2026-11-03, on branch `claude/track-schema-generations-b064c1`; 4,618 tests pass)
- [x] Phase 2 — Derived cards (2026-11-04, same branch; 4,624 tests in 758 suites pass)
- [ ] Roll-out A on every device — build 300000000034 sent to TestFlight 2026-11-04 from main f32e0a66; installing it on each device is [Danny's row in Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Install%20TestFlight%20build%20300000000034%20of%20Cosmic%20Daybook%20on%20the%20Mac%2C%20iPad%20and%20iPhone%2C%20so%20the%20track%20tables%20can%20be%20dropped), and [checking a child's cards afterwards](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20installing%20build%20300000000034%2C%20open%20a%20child%27s%20Current%20Learning%20and%20History%20and%20check%20her%20sequence%20cards%2C%20counts%20and%20next%20lesson%20match%20what%20the%20old%20cards%20showed) is the second
- [ ] Phase 3 — Drop the schema — built 2026-11-04 on branch `claude/track-phase3-drop-schema` (schema 23, backup format 45; the four entities stay as dormant tombstones so sync history survives; 4,619 tests in 759 suites pass). Lands on main only after every device runs 300000000034: [Danny's row in Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Once%20every%20device%20runs%20build%20300000000034%2C%20land%20Phase%203%20of%20the%20track%20plan%20%28branch%20claude%2Ftrack-phase3-drop-schema%2C%20schema%2023%29%20on%20main%20and%20roll%20out%20build%20B)
- [ ] Roll-out B
