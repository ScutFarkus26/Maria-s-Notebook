# Insights and track detail — 2026-09-21

The last two per-student loaders the codebase map listed as whole-table reads: Insights
(`StudentAnalysisService.analyzeStudent`) and the Student Track Detail sheet (`StudentTrackDetailLoader`
plus the `StudentAreaProgressionViewModel` timeline). Measured as on 2026-09-18, outputs pinned.

- `StudentTrackDetailLoadScopeTests.loadMaterialisesOnlyTheStudentsRows`: one student on "Math
  — Chains" (two lessons; the first mastered, presented, with open work and a completed check-in)
  next to 12 classmates carrying the same shape on their own track.
- `StudentAnalysisServiceScopeTests.analysisMaterialisesOnlyTheStudentsRows`: two notes, one
  practice session and one completion in the 30-day window (plus an older note) for the student
  and for each of 12 classmates; a canned model client.

| Measure | Before | After |
|---|---|---|
| Objects registered by one track-detail open (12 classmates) | 76 | 4 |
| Objects registered by one Insights analysis (12 classmates) | 17 | 17 |

Track detail: the child by id (the exact `cloudKitKey` string check kept); lessons by
`SequenceTrackService.lessonCandidates` / `couldEqualPredicate` (the `CONTAINS[cd]` superset of
the trimmed match each caller still applies); her marks by `studentID` + `lessonID IN`; the
timeline's presentations by `lessonID IN[c]` over that superset (what the next-lesson planner
searches); her work by `studentID` + `lessonID IN`; check-ins by `workID IN[c]`. Insights already
read notes and completions by student; a practice session's roster is a Transformable blob, so
the window's sessions are still read whole and filtered in memory.
