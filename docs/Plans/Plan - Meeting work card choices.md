# Meeting work card choices: two rows, and Ready for Next on its own

> **Not started.** Written 2026-10-30 from Danny's talk-through (branch `claude/keep-working-practice-difference-35b458`).
> In short: the meeting's work card asks "keep going or finished?" in one row and "Mastered, Re-present or Rest" in another, and Ready for Next becomes an on/off add-on that goes with any of them except Re-present.

Follows [Plan - Re-present and Ready for Next in meetings](<Plan - Re-present and Ready for Next in meetings.md>) (done 2026-10-07, a8e7dd98), which made Ready for Next an outcome of its own.

## What Danny wants
- He asked what the difference is between Keep Working and Practice. Today **Keep Working** leaves the work open (Working). **Practice** closes it with the verdict Keep Practicing: it's logged, it leaves the Scheduled strip and her open work, and its check-ins are cleared.
- His model (2026-10-30): if the work was an assignment, she keeps working; if she was practicing, she keeps practicing. Either kind can be finished instead. Ready for Next is separate from those. Mastered, Re-present and Rest are a row of their own.
- He wants to mark Ready for Next as well as another choice. Practice and Mastered can both mean she's ready for the next lesson.

## The card

```
✓ Practice Solving for an Unknown Using Multiplication          ↗
  Working · 59 days · last touched Oct 30
  [ Keep Practicing ] [ Finished ]
  [ Mastered ] [ Re-present ] [ Rest… ]
  [ ☐ Ready for Next · Equivalence of Fractions ]
  Note…
```

1. **First row: keep going or finished.**
   - The first button's label follows the kind of work: **Keep Practicing** for Practice work (and untagged work, which the app already shows as Practice, `CDWorkModel.displayKind`); **Keep Working** for Follow-Up, Project and Report work. Both leave the work **open** (Working). That's the change from today's Practice button: the closed Keep Practicing verdict leaves the meeting card. It stays in the work's own status picker and over MCP.
   - **Finished** closes the work with no verdict (status Finished, raw `complete`), the way Ready for Next closes it today.
2. **Second row: Mastered · Re-present · Rest…**, each working as it does today. Re-present and Rest are offered where they are today (Re-present only on work from a lesson).
3. **One choice across both rows.** The work has one status, so picking any button in either row replaces the earlier pick, as the card does today (the earlier pick's close is taken back through its receipt).
4. **Ready for Next is an on/off switch on its own line**, styled so it doesn't read as one of the pick-one buttons, and named with the lesson it will put On Deck.
   - It doesn't change the work's status, and it doesn't count as the card's decision: the tick and "4 of 4 decisions made" still need a choice from the two rows.
   - It goes with any choice except Re-present, which plans this same lesson again: picking Re-present switches Ready for Next off, and the switch is dimmed while Re-present is picked.
   - On Complete & Next (and the Meetings tab's Save to History) it does what it does today: confirms her on this lesson (not mastery), closes her follow-up on its presentation as ready, and puts the next lesson On Deck unless she has had it, mastered it or already has it planned.
   - Offered only on lesson work with a next lesson in its sequence, as today.
5. **Clear Meeting** drops Ready for Next (it had changed nothing yet) and still takes back Re-present. Status choices stay as made, as Mastered and Practice already do today.
6. **A draft from before this change**: a Ready for Next made then already closed its work as Finished, so it reads as Finished with Ready for Next on.

## Code
- `Students/Meetings/Tab/WorkDecisionCard.swift`: the two rows, the label by kind, the switch with the next lesson's name.
- `Students/Meetings/Workflow/MeetingDraftModel+Decisions.swift`: Ready for Next becomes a switch on `readyWorkIDs` with no status change; a status choice forgets only Re-present; Re-present also switches Ready off; Rest treats only Re-present as a lesson decision.
- `Students/Meetings/Workflow/MeetingDraftModel+Fields.swift`: the next lesson's name per lesson, worked out with `lessonsWithNext` from the same one lesson fetch and the same rule as `PlanNextLessonService.findNextLesson`.
- `Students/Meetings/Data/MeetingLessonDecisions.swift` and `+Clear.swift`: filing Ready for Next no longer checks for the Finished status (it no longer sets one); Clear takes back Re-present work only.
- Doc comments that say Ready for Next closes work (`MeetingDraftModel.swift`, `MeetingCloseToken.swift`), and the Ready for Next lines in `docs/Technical notes/Work_Models_Best_Practices.md`.
- Tests in `Cosmic Daybook Tests/Students/Meetings/MeetingDraftStoreTests*.swift`: rewrite the ones that expect Ready for Next to close the work, and add: Mastered with Ready plans the next lesson and stays Mastered; Ready alone leaves the status and the card undecided; Re-present switches Ready off; Rest keeps Ready; Clear drops Ready and leaves a Finished choice; the label follows the kind.
- No schema, backup or MCP change: the draft already stores `readyWorkIDs`.

## Checks
- iOS build and the `MeetingDraftStoreTests` suites; macOS compile-only (the card in Danny's screenshot is the Mac's).
- A look at the card on the iPhone 17 simulator with the Sample Class (one card of each kind), and the Mac layout if it can be rendered.
- Whole suite once at the end.

## Progress
- [ ] Build and test
- [ ] Merge to main
