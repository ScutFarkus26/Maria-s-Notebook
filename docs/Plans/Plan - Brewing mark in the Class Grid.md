# Brewing mark in the Class Grid: a planned cell says when its lesson is waiting

> **Working on it.** Building on `claude/class-grid-brewing-mark-6e0d2d` since 2026-11-10; not on main. Written 2026-11-10 from Danny's report that the grid "doesn't line up with the lesson inbox", in a session that was open in Tide's folder; Danny picked "Grid shows Brewing" and mark A (the dot in the ring) the same day.
> In short: a cell Danny planned from the Class Grid shows a Brewing mark (the orange Planned ring with the grey Not yet dot inside) when its Inbox lesson sits under Brewing, and its card says what it is waiting on, so the grid and the Inbox agree.

## Goal
When Danny adds a child to the Inbox from the Class Grid's Checklist, the cell turns Planned. He then opens Lessons & Work and can't find the lesson, because the Inbox opens on Ready and the lesson went to Brewing: the children on it haven't finished the lesson before. The grid gives no hint. When this is done, the cell itself says which Inbox tab holds the lesson, the card names what it is waiting on, and the key counts Brewing apart from Planned. The Inbox's rule doesn't change.

## What was found (2026-11-10)
- **The grid's marks do reach the Inbox.** Add to Inbox (`ClassAreaChecklistViewModel.addStudentToUnscheduledLesson`, `Lessons/Checklist/ViewModels/ClassSubjectChecklistViewModel+CellActions.swift`) puts the child on the lesson's undated `CDLessonAssignment`, or makes one with `PresentationFactory.makeDraft`. The Inbox (`PresentationsViewModel.partitionIntoReadyAndBlocked`, `Presentations/Overview/PresentationsViewModel.swift`) reads every undated, not-given assignment and splits them with `BlockingAlgorithmEngine.checkBlocking(forBatch:…)`: blocked ones are Brewing, the rest Ready.
- **A lesson is Brewing when any judged child on it isn't ready**: the lesson before it in the sub-area (by `orderInSequence`) wasn't given to her, or her practice on it is open, or it isn't confirmed, per that lesson's progression rules (`LessonProgressionRules`, both gates on by default). `manuallyUnblocked` skips the check.
- **The grid draws both the same.** `StudentChecklistRowState.displayStatus` is `.planned` whenever she is on a not-given assignment (`isScheduled`) or next on her year plan; the lesson before only decides Ready against Not yet for a cell with no plan.
- **Live data, Math › Decimal Fractions** (read through the connector): Converting a fraction with Instrument for Converting (7 children; the lesson before, Division with decimals by a Unit Divisor, not given to them), Addition with decimals (5; Formation and Reading of Quantities given 2026-11-10, practice open) and The Effects of Multiplying or Dividing a Number by a Power of Ten (6; Converting a fraction on Paper not given) are all undated Inbox lessons, and by the rule all three are Brewing. The Brewing tab itself wasn't looked at.
- **Presenting does reach the grid.** A cell is Presented when the child is on a given assignment, read each time the Checklist appears (`ClassGridEngine.buildMatrix`). The Inbox row's Presented button records only the children who are here.

## Decisions
1. **The grid shows it; the Inbox keeps its rule** (Danny, 2026-11-10). Ruled out: sending a lesson planned from the grid straight to Ready (marking it `manuallyUnblocked`), which would empty Brewing of everything planned from the grid.
2. **Mark A: the Planned ring with the Not yet dot inside** (Danny, 2026-11-10, from a mockup). Ruled out: B, the ring turned grey, which is easy to mistake for Ready's grey ring.
3. **Brewing is a flag on a Planned cell, not a new rung.** `ChecklistDisplayStatus` stays as it is: all four Class Grid views, the ladder's order, the card's five steps and the row summary read it, and a brewing cell is still Planned on that ladder. The flag rides beside it the way `checkFirstReasons` rides beside Ready. Ruled out: a `.brewing` case, which every `switch` over the status in Three Years, Children, Recall and the student page would have to answer.
4. **One rule, shared.** The grid asks the same function the Inbox asks, with the same inputs (open work plus the closed work of the preceding presentations, the preceding lessons' mastery marks, and the enrolled, shown children as the judged set). Move the Inbox's gathering of those inputs out of `PresentationsViewModel` into one place both call, so the two can't drift; a test pins that they agree. The grid's own Ready against Not yet rule (`ReadyForNextEngine`, for cells with no plan) is not touched.
5. **The mark follows the Inbox row.** The Inbox holds a whole group while any one child isn't ready, so every child on that assignment gets the Brewing mark, and the card names who it is waiting on when it isn't her.
6. **Only an undated Inbox lesson can be Brewing.** A dated plan and a year-plan entry stay plain Planned.
7. **Checklist view only.** Three Years, Children and Recall don't draw Planned from the Inbox and stay as they are.

## The change
- **State** (`Students/Progress/StudentChecklistState.swift`): `StudentChecklistRowState` gains `isBrewing: Bool` and `brewingHeldBy: [UUID]` (the children on her Inbox assignment who aren't ready, in roster order), both defaulted so other callers compile.
- **Engine** (`ClassGrid/Engine/ClassGridEngine+Checklist.swift`, `fillRows`): for the row lessons' undated, not-given assignments, one batch call to the shared blocking check; a cell whose `plannedCandidate` is one of the blocked assignments is brewing. `buildCellState` picks `nonPresented.first`; when she is on both a dated and an undated plan, the dated one wins and the cell is plain Planned. `rebuildRows(touching:)` already rebuilds the rows after a touched lesson, which is what a change to the lesson before needs.
- **Shared inputs** (new file in `Presentations/Planning/`, e.g. `InboxPlacement.swift`): the fetches now in `PresentationsViewModel+ChangeInputs.swift` (`fetchClosedPrecedingWork`, `fetchPrecedingMasteryMarks`) and the call in `partitionIntoReadyAndBlocked`, as one function returning the blocking results; `PresentationsViewModel` calls it and keeps its hashes.
- **Mark** (`Lessons/Checklist/Views/ChecklistMark.swift`): `var brewing: Bool = false`; with `.planned` it draws the dashed orange ring plus the `.notReady` grey dot at its center. `ChecklistMark.label` says "Brewing". Add it to the file's preview. `ClassChecklistSmartCell` and `ChecklistCellCard` pass the flag.
- **Card** (`Lessons/Checklist/Model/ChecklistCellCardText.swift`): title "Brewing."; detail "In the Inbox under Brewing, waiting on <lesson before>." when she holds it, "In the Inbox under Brewing, waiting on Avital B and 2 others for <lesson before>." when others do. A ready Inbox plan changes from "In the Inbox." to "In the Inbox, under Ready."
- **Hover and VoiceOver** (`Lessons/Checklist/Model/ChecklistCellDescription.swift`): "Brewing: waiting on <lesson before>".
- **Key** (`Lessons/Checklist/Model/ChecklistStatusCounts.swift`, `Lessons/Checklist/Views/ChecklistStatusBar.swift`): a `brewing` count; Planned shows planned less brewing; a Brewing item after Planned, the way Check first follows Ready, with the help text "In the Inbox under Brewing: the children haven't finished the lesson before". Planned's help text stays.
- **Docs**: the Class Grid section of the manual in `Documentation/Manuals/` and the mark's header comment.

## Tests
New suite `Cosmic Daybook Tests/Lessons/Checklist/ChecklistBrewingTests.swift`, on `CoreDataTestHelpers.makeInMemoryStack()`:
1. An undated plan whose lesson before wasn't given: brewing, held by her.
2. The lesson before mastered, or given with both gates off: Planned, not brewing.
3. A group of three where one isn't ready: all three brewing, `brewingHeldBy` names the one.
4. `manuallyUnblocked`: not brewing.
5. A dated plan, and a year-plan entry alone: not brewing.
6. A withdrawn or hidden child on the assignment doesn't hold it (the judged set).
7. Agreement: for a seeded store, the cells the grid marks brewing are exactly the children on `PresentationsViewModel.blockedLessons`.
8. `rebuildRows(touching:)` after the lesson before is presented and confirmed gives what `buildMatrix` gives (the pattern in `ChecklistIncrementalUpdateTests`).
9. Counts: Planned and Brewing add up to the old Planned.
10. Card, hover and VoiceOver wording, both "held by her" and "held by others".

Run with `-only-testing:` for this suite, `ChecklistDisplayStatusTests`, `ChecklistIncrementalUpdateTests`, `ChecklistMatrixBuilderEquivalenceTests`, `ClassGridEngineTests`, `ReadinessAgreementTestsFix1103`, `PresentationsReadinessFix1103P` and `PresentationsBacklogTests`; then the whole suite once, and iOS, Mac and Daybook Assistant builds with no warnings.

## Checks by hand
- A screenshot of the mark's preview and of a Checklist row in the Sample Class, on a simulator, in light and dark.
- Danny's, on the Mac after a roll-out (a row in Tide when the build lands): Math › Decimal Fractions shows the three lessons above as Brewing, and each is under Brewing in Lessons & Work.

## Not in this plan
- A dated lesson whose day passed without being given (Multiplication of a Decimal Fraction by a Decimal Fraction, Sarah M and Tiferet P, 2026-11-05) shows Planned in the grid and only under Earlier days in the Scheduled strip. Left alone: `CalendarForwardShiftService` says such a lesson is the guide's to place.
- Add to Inbox takes the first undated assignment of the lesson in fetch order, which put Dalia's Addition with decimals on a separate one shared with a withdrawn child. Worth its own fix.
- The grid's Not yet rule and the Inbox's rule are two engines (`ReadyForNextEngine`, `BlockingAlgorithmEngine`) that can disagree for a cell with no plan; `ReadinessAgreementTestsFix1103` covers part of it.

## Open questions
None waiting on Danny.
