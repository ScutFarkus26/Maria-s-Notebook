# Lesson Recall & Retention — Implementation Plan

Status: **Implemented v1 — full test suite green** — built 2026-06-23 · Owner: Danny · Created 2026-06-23
(Deferred follow-ups: spaced-interval Settings UI, photo capture, per-covered "check anyway"
override, and embedding the retention summary in the Progress Dashboard card. Manual smoke on a
populated device still recommended to confirm the additive Core Data change migrates cleanly.)
Depends on: **School Year Separation** for the lens, the configurable year start date, and
`SchoolYearFilter` predicate factories — these are now on `main` (merged via `d49bb0bc`), so
recall builds directly against them with no branch dependency.

Reconciliation notes (2026-06-23): mastery (`CDLessonPresentation`) lives in the **shared**
store, but recall checks (`CDLessonRecallCheck`) are placed in the **private** store by design
— they are each teacher's own assessment records, not part of the classroom CKShare. The
working set is therefore cross-store: the engine fetches mastery (shared) + lessons (shared) +
recall rows (private) separately and joins by string IDs in memory, with `originalMasteredAt`
snapshotted onto each recall row so the dashboard never re-joins to shared mastery.

## Overview

After a break (summer above all), let a guide re-check what children still remember from
lessons already marked **mastered**, record the result, and track retention over time —
*without ever overwriting the mastery record*. A recall result is a new event recorded
*alongside* `CDLessonPresentation`, never an edit to it.

Two ideas carry the feature:

1. **Recall is a separate, additive layer.** `CDLessonPresentation.masteredAt` is stamped
   once and never cleared. We add `CDLessonRecallCheck` records that reference a presentation;
   the mastery history stays intact, cumulative reports keep working, and CloudKit stays
   additive.
2. **Check the frontier, not the ladder.** The curriculum is a sequence: proving a more
   advanced lesson proves the foundational ones beneath it in the same strand. So we surface
   only the top mastered lesson per strand and treat the rest as *covered*.

## Principles (and why)

1. **Never destroy mastery.** A recall check is additive. `masteredAt` and the presentation
   state are untouched; a "forgotten" result feeds the follow-up loop but leaves the history
   readable as a timeline (mastered → re-checked → shaky).
2. **Rides on data we already keep.** Strand = `CDLesson.area` + `CDLesson.sequence`; order =
   `CDLesson.orderInSequence`; mastery = `CDLessonPresentation` (`state == .proficient`,
   `masteredAt`). No new data entry is required to seed the queue.
3. **Honest stats.** A covered lesson still counts toward retention, but flagged as *inferred*
   (`source = .covered`) not *observed*, so "78% held" never overstates what was actually seen.
4. **Frictionless in the moment.** One tap per lesson (still has it / shaky / forgotten),
   optional note and photo, `Save & next` down the queue.
5. **Additive & reversible.** New entity in the private store, no schema changes to existing
   entities. Disabling the feature hides a section; it cannot lose data.

## Decisions locked (2026-06-23)

| Decision | Choice |
|---|---|
| **Placement** | Inside the **Students** area, beside the Progress Dashboard (no new tab) |
| **Outcomes** | **Three** — `retained` ("still has it") / `shaky` / `forgotten` |
| **Triggers** | **Both** — a start-of-year sweep **and** continuous spaced re-checks |
| **v1 scope** | **Queue + check + dashboard** (timeline + parent report = later) |
| **Coverage scope** | **Within-strand only** for v1; cross-strand is a later toggle |
| **Queue UX** | Collapse each strand to its frontier with a **"covers N" count + expander** |

Defaults assumed (override anytime): covered lessons get a stamped
`retained · covered-by` record; `forgotten` sets `needsAnotherPresentation` and drops a
re-presentation into planning while keeping `masteredAt`; `shaky` sets `needsPractice`; ties
at the same `orderInSequence` are treated as co-frontiers (check both).

## Data model

New entity `CDLessonRecallCheck`, **private store** (teacher activity, co-located with
`CDLessonPresentation`/`CDLessonAssignment`/notes/work). Follows project Core Data conventions:
no unique constraints, enums as `String` raw, FKs as `String`, all properties optional or
defaulted, `modifiedAt` for conflict resolution.

```swift
@objc(CDLessonRecallCheck)
public class CDLessonRecallCheck: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String?          // FK (String, per convention)
    @NSManaged public var lessonID: String?           // FK
    @NSManaged public var presentationID: String?      // FK → CDLessonPresentation
    @NSManaged public var checkedAt: Date?
    @NSManaged public var outcomeRaw: String?          // LessonRecallOutcome
    @NSManaged public var sourceRaw: String?           // RecallSource: observed | covered
    @NSManaged public var coveredByLessonID: String?   // set when sourceRaw == "covered"
    @NSManaged public var originalMasteredAt: Date?    // snapshot of masteredAt at check time
    @NSManaged public var note: String?
    @NSManaged public var photoRef: String?            // optional; reuse existing attachment path
    @NSManaged public var schoolYearKey: String?       // lens year this recall belongs to
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
}

enum LessonRecallOutcome: String, CaseIterable, Codable {
    case retained   // "still has it"
    case shaky      // needs a quick brush-up
    case forgotten  // needs a re-presentation
}

enum RecallSource: String, Codable {
    case observed   // a check you actually ran
    case covered    // inferred from a retained frontier lesson above it
}
```

Three user-facing outcomes are preserved; `source` is the orthogonal axis that keeps
covered/inferred records out of the "observed" stats without inventing a fourth outcome.
`daysSinceMastery` is computed (`originalMasteredAt → checkedAt`) for later decay analysis.

## The frontier rule (within-strand subsumption)

Strand = `(area, sequence)`. For a student:

1. Fetch `CDLessonPresentation` where `state == .proficient`, join to `CDLesson`, group by
   `(area, sequence)`, sort each group by `orderInSequence` (mirrors
   `StudentSubjectProgressionViewModel`).
2. The **frontier** = max `orderInSequence` mastered lesson in the strand. Only the frontier
   is queued. "covers N" = the count of lower mastered lessons in the same strand.
3. On a **retained** frontier result → write `covered` records (`outcome = .retained`,
   `coveredByLessonID = frontier`) for each lower mastered lesson. Idempotent per
   `(student, lesson, schoolYearKey)`.
4. On a **shaky/forgotten** frontier result → do **not** cover. Instead drill down: surface
   the next lesson down via `BlockingAlgorithmEngine.computePrecedingLesson()` (reused in
   reverse) so the guide localizes where the chain broke.
5. **Co-frontier tie:** if two lessons share the max `orderInSequence`, queue both.
6. **Override:** the expander lists covered lessons each with a *check anyway* action that
   promotes one to an observed check.

Cross-strand coverage (following `CDLesson.prerequisiteLessonIDs` across strands) is **off**
in v1 — a later toggle that simply widens what counts as "covered."

## Triggers (both)

- **Start-of-year sweep.** On first launch on/after the school-year start date, eligible =
  `proficient` presentations with `masteredAt < currentSchoolYear.startDate` and no
  `CDLessonRecallCheck` for that `(student, lesson)` with `schoolYearKey == currentYear.key`.
  Collapsed to frontiers, grouped by student.
- **Continuous spaced re-checks.** A frontier becomes "due" when
  `now − max(masteredAt, lastRecallCheckedAt, lastObservedAt)` exceeds a spacing interval.
  v1 ships a single configurable interval (default ~90 days) producing a "due for re-check"
  list; widening intervals (30 → 90 → 180 → each break) are a tuning follow-up.

The queue merges both sources, grouped by student, each strand collapsed to its frontier.
Eligibility predicates reuse `SchoolYearFilter` so the lens and the recall list agree.

## Outcomes & the follow-up loop

| Outcome | Record | Side effects (keep `masteredAt`) |
|---|---|---|
| `retained` | observed check; cover lower rungs | bump `lastObservedAt` |
| `shaky` | observed check | set `needsPractice`; resurfaces sooner |
| `forgotten` | observed check | set `needsAnotherPresentation`; queue a re-presentation into planning |

Follow-up flags currently live on `CDLessonAssignment` (`needsPractice`,
`needsAnotherPresentation`, `followUpWork`) — confirm they're reachable from the
presentation record, or mirror equivalents, during Phase 2.

## Placement & screens (inside Students)

1. **Recall queue** — grouped by student, each strand one frontier row with "covers N" +
   expander; standalone lessons checked directly; already-checked rows show their result
   inline. Header reflects the lens and the within-strand/cross-strand state.
2. **Run a check** — push/sheet: lesson + mastery context, three outcome buttons, optional
   note + photo, `Save & next`.
3. **Retention dashboard** — surfaced in the existing Progress Dashboard: class-held %,
   checked count, re-present count; per-student retention bars; "fades over summer"
   class-wide list (lowest first) as a curriculum signal. Observed vs covered are countable
   separately.

## Backup & store routing (do not skip)

`BackupCoverageTests` asserts `BackupEntityRegistry.allTypes` ≡
`BackupWriter.serializedEntityNames` ≡ `BackupImporter.handledEntityNames`. **Adding
`CDLessonRecallCheck` without backup coverage is a red test, not a future format bump.** So
Phase 0 must also:

- Register the entity in `Backup/Core/BackupEntityRegistry.swift`.
- Add a DTO transformer in `Backup/Export/BackupDTOTransformers*.swift`.
- Add an importer in `Backup/Import/BackupEntityImporter+*.swift`.
- Route it to the **private** store and confirm it round-trips (the coverage + round-trip
  tests will enforce this).

CloudKit: additive-only, string FKs, `modifiedAt` conflict resolution — no changes to any
existing entity.

## Phasing

- **Phase 0 — Model & backup.** `CDLessonRecallCheck` in the model + private store;
  `LessonRecallOutcome` / `RecallSource`; backup registry/DTO/importer/coverage; unit-test
  round-trip. *(No UI.)*
- **Phase 1 — Frontier engine & queue.** Strand grouping, frontier + co-frontier, "covers N",
  eligibility (sweep + spaced), covered stamping (idempotent), drill-down. Recall queue view
  in Students with count + expander.
- **Phase 2 — Check flow.** Three-outcome sheet, note + optional photo, `Save & next`,
  wire outcomes → follow-up flags + planning.
- **Phase 3 — Dashboard.** Retention cards + per-student + fades-over-summer in Progress
  Dashboard; observed/covered split.
- **Later (post-v1).** Per-lesson recall timeline; parent recall report via
  `ReportGeneratorService` / `AIReportService` (cf. `CDDevelopmentSnapshot`); cross-strand
  coverage toggle (`prerequisiteLessonIDs`); spacing-interval tuning UI.

## Edge cases

- **Proficient but `masteredAt == nil`** → fall back to `presentedAt`; fail-open (include
  rather than silently drop), matching the lens's fail-open rule.
- **Un-mastered later** (state changed away from `.proficient`) → gate on *current* state, so
  it doesn't enter the recall queue.
- **Withdrawn students** → respect the roster filter (`dateStarted`/`dateWithdrawn`).
- **Lesson removed from curriculum** → recall records keyed by `lessonID` survive; show a
  graceful "lesson no longer in library" state.
- **Covered idempotency** → keyed by `(student, lesson, schoolYearKey)` so re-running a sweep
  never duplicates covered records.

## Testing

- Frontier computation: collapse, ties, "covers N" correctness, drill-down on failure.
- Eligibility predicates: start-of-year sweep + spaced interval, lens agreement.
- Covered stamping: created on retained, *not* on shaky/forgotten, idempotent.
- Dashboard math: observed vs covered counted correctly.
- Backup round-trip + `BackupCoverageTests` green.
- Keep the suite green (114/0 baseline) — any red is a real regression.

## Build notes

- Auto-research current Apple docs (Core Data / CloudKit / SwiftUI) before coding each phase.
- Zero-warnings + SwiftLint; `@Observable @MainActor` view models; `NSFetchRequest` +
  `NSPredicate` (not `@Query`/`#Predicate`); `@FetchRequest` in views.
- Build/test with the 27-beta toolchain (`DEVELOPER_DIR=$HOME/Downloads/Xcode-beta.app/...`).
- Recall depends on School Year Separation infra currently on
  `feature/school-year-separation`; sequence the recall branch after that merges (or branch
  from it).
