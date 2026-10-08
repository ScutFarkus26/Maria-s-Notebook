# Re-present and Ready for Next in meetings

> **Not started.** Written 2026-10-07. Danny asked for "represent" and "ready for the next lesson, on the board" on the meeting work cards; both are built and unit-tested on branch `claude/add-represent-work-review-030aef` (uncommitted).
> In short: review the two new meeting buttons, look at them on the iPhone and iPad simulators, then merge them to main.

## Goal

In a student meeting, every work card under Needs a Decision (and an expanded Open Work row) has two more buttons. **Re-present** closes the work as Incomplete and, on Complete & Next, puts the same lesson On Deck again as a second pass. **Ready for Next** closes the work as Done, with no mastery mark, and on Complete records the child as ready on that lesson and puts the next lesson in its sequence On Deck. When this plan is done, both are reviewed, seen working in the app, and on main.

## Progress
- [x] Phase 1: Review and fix (session: here) · est. ~1% weekly. The three known fixes landed with tests (15 in the suite pass). On Danny's call at close-out (2026-10-07), the review agent's pass over the code was skipped; the plan review had already found these three.
- [x] Phase 2: Look, build, merge (session: here) · est. ~1–2% weekly. Merged with the iOS and Mac builds and the meeting suite. Skipped on Danny's call: the simulator look, the Assistant build (nothing it compiles changed), and the whole-suite run. Trying both buttons in a real meeting, on the Mac and the iPad, is a row in Cosmic Daybook's list in Tide.

## Cost

About 2–3% of the weekly limit (Max), both phases in this session. At planning (2026-10-07) 92% was used, leaving 8% until Fri 9 Oct, 1 pm. Fits. Extra usage is at $40 of its $50 monthly cap, so nothing here should spill into it.

## Decisions

- **What's already built** (uncommitted on this branch): `Students/Meetings/Tab/WorkDecisionCard.swift` (the two buttons, shown only when the work has a lesson), `Students/Meetings/Workflow/MeetingDraftModel.swift` (`represent`, `readyForNext`, `representWorkIDs`, `readyWorkIDs`, and the Complete steps `persistRepresentations` / `planNextLessons`), `Students/Meetings/Data/MeetingPersistenceService.swift` (two optional draft fields, kept through the Meetings tab's saves), and 3 new tests in `Cosmic Daybook Tests/Students/Meetings/MeetingDraftStoreTests.swift`. All 14 tests in that suite passed on 2026-10-07.
- **Re-present closes the work as Incomplete** (Danny, 2026-10-07). Ruled out: keeping it open, which would leave it counted as stuck next to the new presentation.
- **Ready for Next closes the work as Done, not Mastered** (Danny, 2026-10-07), following his 2026-09-11 rule that being ready isn't mastery. Ruled out: Mastered, and keeping the work open.
- **"The board" means On Deck**: an unscheduled draft presentation. That's where a presentation's own Ready for Next already sends the next lesson (`PresentationSessionCommit.planNextLesson`). Ask Danny if he meant somewhere else.
- **The status changes when the button is tapped, and the lesson is planned on Complete & Next**, the same split as the card's other buttons (immediate) and Lesson Requests (on Complete). Choosing another button before Complete takes the plan back. Skip for Now keeps it in the draft.
- **Both reuse what presentations already do**, so the records match. Re-present sets `needsAnotherPresentation` on the old presentation, resolves its follow-up as `.supportOrRepresent`, and plans through `CaptureFollowUpPersistence.createRepresentationIfNeeded` (which writes the "second pass" line and won't plan the lesson twice). Ready confirms the child on the presentation (`confirmStudent`), resolves the follow-up as `.readyForNextPresentation`, and plans through `PlanNextLessonService`, skipping a child who already has that lesson planned.
- **A cleared meeting must not leave work closed with nothing planned.** The work closes on tap, but the plan lives only in this device's draft, so Clear (or abandoning the draft) would silently drop the lesson. Phase 1 makes Clear reopen any Re-present or Ready work as Working. A meeting finished on another device can't see this device's draft; that's accepted, the same as every other draft field.
- **"On Deck" can become "scheduled".** `PlanNextLessonService.planLesson` promotes from the Year Plan when a matching entry exists, the same as a presentation's Ready for Next, so the next lesson can land already scheduled. Kept on purpose for consistency.
- **No schema or backup change.** The new draft fields live in the per-child draft in UserDefaults, not in Core Data.
- **Merge to main only, no roll-out** (Danny, 2026-10-07). It goes out with the next roll-out.
- **No Mac debug run.** A Mac debug build shares the app's bundle ID, and its test host opens the live store (see memory `test-host-opens-live-store`). The Mac look goes to Danny as a Tide row, checked after the next roll-out.
- **No manual update.** The user manual doesn't describe the meeting decision buttons.

## Apple guidance

Not applicable. The change adds no new Apple API: the buttons reuse the card's existing `FlowLayout`, `Button` and `.help` code.

## Phase 1: Review and fix
- Who: one `Plan` agent as reviewer (Opus 5.5, default effort; the change closes work and plans presentations, so a missed edge case could put a wrong lesson On Deck or close work silently), then fixes in the main session (Opus 5.5 high).
- Steps:
  1. The reviewer reads `git diff main` on this branch and checks it against `PresentationSessionCommit.swift` (its `apply` and `planNextLesson`) and `CaptureFollowUpPersistence.swift` (`.represent`, `.readyForNextLesson`). Look for: double plans, a plan left behind when a choice is changed, a failed status write that still records the choice, work shared by several children (`WorkGrouping`), work with no presentation, the last lesson in a sequence, a child already On Deck for the lesson, and Complete's rollback when a save fails. At most 15 lines back.
  2. Known fixes, done alongside the review in the main session:
     - Double plan: a Lesson Request for the lesson Ready for Next plans makes two On Deck drafts (`planNextLessons` runs before the requests loop, which skips only re-presented lessons). Have `planNextLessons` return the lessons it planned (or found already planned) and skip those in the requests loop too.
     - Clear: `clear()` reopens the work in `representWorkIDs` and `readyWorkIDs` as Working through `WorkLogService`, before emptying the sets.
     - A failed save in `decide` shows a toast but still marks the work reviewed; make `represent` / `readyForNext` record nothing when that save fails.
  3. Fix what else holds up from the review. Each fix gets a test in `MeetingDraftStoreTests`, plus tests for switching Re-present to Ready and back on one work, and for a reloaded draft (Skip for Now) keeping the choice.
- Cost: ~1% of weekly (one review agent ~0.5%, plus three small fixes and tests in files already read).
- Done when: the three known fixes and the reviewer's findings are fixed or answered in one line each under this phase; `-only-testing:"Cosmic Daybook Tests/MeetingDraftStoreTests"` passes on the leased simulator (`-parallel-testing-enabled NO`, 1 simulator).
- Hand off: no.

## Phase 2: Look, build, merge
- Who: main session (Opus 5.5 high).
- Steps:
  1. Build the app for the leased iPhone 17 with `Scripts/locked_xcodebuild.sh`, launch it in the Sample Class, open Meetings, pick a child whose stuck work came from a presentation of a lesson that has a next lesson in its sequence (check the lesson before tapping; if the Sample Class has none, add one through the app), and take screenshots: a card before any choice, after Re-present, after Ready for Next, and the card at the largest text size. Tap Complete & Next, then check: On Deck (or the schedule, if the Year Plan promoted it) shows the same lesson again with its second-pass note and the next lesson; the old presentation shows it needs another; both works have left Needs a Decision. Repeat on an iPad (`sim-lease --type` an iPad) for the wide two-pane meeting layout. Fix any layout problem.
  2. Full builds: iOS app, macOS app, and the Daybook Assistant (it shares model files). Run the whole unit suite once.
  3. Commit on this branch, with this plan and `docs/Start here.md`. Fetch and rebase onto the latest `origin/main`; if main moved, re-run the whole suite. Then land on main. The main checkout may be on another session's branch, so use `git update-ref` (memory `merge-when-checkout-shared`), not a merge there. Push.
  4. Cosmic Daybook's list in Tide (`add_action`): one row to try both buttons on the Mac and on a real meeting after the next roll-out, including that the lessons show up On Deck.
- Cost: ~1–2% of weekly (two simulators, three platform builds, one whole suite).
- Done when: the screenshots show both buttons and their selected state on iPhone and iPad with nothing cut off; the planned lessons, second-pass note, flag and cleared cards show after Complete; iOS, macOS and Assistant builds succeed; the whole suite passes; `git log origin/main` shows the commit; the Tide row exists; `sim-lease --done` has run.
- Hand off: no.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board, if the plan lists one.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (Cosmic Daybook's area, `add_action`), skipping ones already there. Tide holds the row; the repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets the plan's status line (`> **Working on it.**` after a phase, `> **Done <date>** (<commit>).` after the last, checked against main) and runs `docs-index` so the map follows.
7. If the next phase is a fresh session, print its starter prompt. (Both phases run here.)

## Open questions
- Is "the board" On Deck? The plan assumes so (see Decisions).
