# Per-student loaders — 2026-09-18

Two of the "per-student loaders" listed as open hot spots in the efficiency-pass
codebase map: the Student Progress tab's `loadData` (eight whole-table fetches on
every open of a student) and `SequenceTrackService` (whole lesson, step, mark,
enrollment and student tables re-read on every recorded presentation, and once per
cell in the checklist batch loops).

## How it was measured

Unit tests on the iPhone 17 simulator (iOS 27.0, Debug), each seeding an in-memory
stack, resetting the context, running the loader once and reading
`registeredObjects.count`: every registered object is a row that was faulted in,
decoded and held by the view context. The same tests pin the outputs (ids, counts,
order, records written) before and after, so the numbers below are for identical
results.

- `StudentProgressTabLoadScopeTests.loadMaterialisesOnlyTheStudentsRows`: one
  student on one two-step track (one mastered), one track note, one open report,
  one project, next to 12 classmates each carrying the same shape on their own track.
- `SequenceTrackServiceScopeTests.enrollAndCheckMaterialiseScopedRows`: 30 lessons
  in three sequences of 10, 12 students who have each mastered the first lesson of
  every sequence, a track already defined for Math — Chains; then
  `autoEnrollInTrackIfNeeded` + `checkAndCompleteTrackIfNeeded` for one student.

Static count (from the code): the progress tab went from 8 whole-table fetches to
8 predicated fetches plus one `fetchLimit = 1` lesson lookup per active track and
per untitled report. The service went from 2–5 whole-table fetches per call to the
same number of predicated fetches.

## Numbers

| Measure | Before | After |
|---|---|---|
| Objects registered by one Student Progress tab load (12 classmates) | 114 | 18 |
| Objects registered by one enrol + completion check (30 lessons, 12 students) | 90 | 24 |

What remains in the "after" columns is the student's own rows plus, for the
progress tab, every active project (the roster is a Transformable blob, so it
cannot be scoped in the store; the class has a handful). On the live store the
lesson table is the whole curriculum, so the ratio there is larger than the
fixture's.

## What changed

- `StudentProgressTabViewModel.loadData`: enrollments, marks and work rows are
  fetched by `studentID`; tracks, steps and presented assignments by the active
  tracks' ids; track notes by the active enrollments' ids (`IN[c]`, matching the
  case-insensitive `UUID(uuidString:)` link); projects by `isActive`. Lessons are
  no longer loaded at all: `lesson(for:)` fetches one by id on demand (name-sorted,
  `fetchLimit = 1`, so a duplicate resolves to the same record the name-sorted
  table scan chose). Each fetch keeps the sort the whole-table fetch had.
- `SequenceTrackService+ScopedReads`: `CONTAINS[cd]` on area/sequence (and
  `CONTAINS` on the track title) as a store-side superset of the trimmed,
  case-insensitive equality the service still applies in memory; steps by
  `track.id`; enrollments by track and student; students by parsed canonical ids;
  marks by student, state and the sequence's lesson ids. An empty area or sequence
  reads everything, as before, since `CONTAINS ""` would not be a superset.
- All reads stay managed-object fetches (not dictionary fetches), so unsaved
  lessons, marks and tracks in the caller's context are still seen, which the
  `saveChanges: false` callers rely on.

## Deliberately unchanged

- Projects on the progress tab are still filtered in memory (Transformable roster).
- The whole-table reads in `DataCleanupService` merges, `SampleClassroomSeeder`
  and the backup importer are one-shot maintenance, not per-student paths.
