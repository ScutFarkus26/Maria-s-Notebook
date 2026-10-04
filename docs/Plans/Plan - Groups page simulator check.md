> Archived 2026-10-04: built and on main.

# Groups page: simulator check

> **Done 2026-10-03** (b0c2a6f0).
> In short: Simulator check of the Groups page on iPad and iPhone, with three layout fixes.
> Run on the iPad and iPhone simulators; three small layout fixes are on main.

## Goal
See the Groups page (main 158c2bce) running for the first time, on an iPad and an iPhone simulator, with enough fake data that every kind of line on a card shows up, and fix what's wrong. Danny gets screenshots of each screen, a pass/fail per check, and small bugs fixed on main; anything bigger goes to Tide. The build session never saw it on screen because the simulator service hung (2026-10-03). Background: `Plan - Groups page.md` (Decisions 1–7, Review notes) and the user manual's "## Groups" section say what each screen should show.

## Progress
- [x] Phase 1: seed, check, fix (session: fresh, 2026-10-03)

### Phase 1 results
Every check passed on the iPad Pro 13-inch (M5) and iPhone 17 Pro simulators (Sample Class, seeded). Three small layout fixes, all in `Groups/`:
- A card showed an overdue wait in orange (`AppColors.warning`), the color the same row uses for "practice not done", while the ladder used the Lesson Age overdue color. Cards now use `palette.overdue` too (`GroupCard.swift`).
- The ladder named the area twice: as the navigation title and again under the sequence name. The header line is gone (`SequenceLadderView.swift`).
- In the one-child row the child's wait floated mid-row; it now lines up at the right like the cards (`SinglesRow.swift`).

| Check | Result |
|---|---|
| iPad 1: Sidebar → Planning → Groups, title, level picker, area chips with counts (Language 2, Math 3), 3-column grid, one-child row expands in place | Pass |
| iPad 2: lesson name, "Area · Sequence", "k of n", "Maya S" names, waits, orange practice reason, dashed could-join, Confirm, "Planned with Leah H · Oct 6"; nothing clipped | Pass (overdue color fixed) |
| iPad 3: Plan opens the sheet with exactly the 4 ready children ticked; after Plan the W2 card leaves and its could-join ghosts on W3 go with it | Pass |
| iPad 4: Confirm on a card moves Rina to Ready after the refresh | Pass |
| iPad 5: ladder steps, tiers (Ready, Practice open, Not confirmed, Planned), not started / finished counts, ‹ › within Math, Confirm on the ladder marks only Eli of the two on one assignment | Pass (duplicate area fixed) |
| iPad 6: Today's "Ready for a next lesson" shows 5 lessons in the page's order; "See all in Groups ›" opens Groups | Pass |
| iPad 7: level picker (Upper) narrows the cards and the chips go to Language 1, Math 2; an area chip filters | Pass |
| iPhone: More → Groups is a list; the ladder pushes and back works; Today's link reaches Groups; tap targets 44 pt | Pass |

What differed from the plan:
- **Seeding.** The Sample Class seeder's own history (27 presentation rows, 5 assignments) puts one-child records across every sequence, so the seed script deleted them before adding the scenario, and added one mastered row (Rina, W5) so the seeder (which seeds only into an empty table) doesn't put them back; it doubles as the ladder's "finished" child. A second G1 assignment (Miriam and Eli, unconfirmed) was added later for the ladder's per-child Confirm. The scripts lived in the session's scratchpad (`cdsql.py`, `seed_lessons.py`, `seed_ready.py`, `seed_history.py`).
- **Onboarding** on the iPhone was skipped with `defaults write … hasCompletedOnboarding -bool YES` before first launch.
- **Out of scope, to Tide (Build & fix):** on the iPad in the Sample Class, the toolbar's "Sample Class · 2026–2027" control draws over the banner's "Return to My Class" button at the top right (every page; the iPhone is fine).
- Noticed, not filed: the floating + button sits over the bottom-right of every scrolling page on the iPhone (it covers part of a card's full-width Plan button until you scroll); the Plan sheet's title "Plan Presentation" appears twice. Both are app-wide, not Groups.

Build board: https://claude.ai/artifact/VZpfwHWT7cGz1vkn3xNzNm (milestone 26 "Verify & land", rows `grp-ipad`, `grp-iphone`).

## Decisions
- **Seed the simulator only** (Danny, 2026-10-03). Fake records go straight into the simulator's copy of the notebook with SQL. No app change; the Sample Class seeder stays as it is. Ruled out: teaching the seeder to make ready groups (an app change Danny didn't want for this).
- **Why seeding is needed:** in the Sample Class each fake child is mastered on a different lesson and has already had its successor, so the ready queue never puts two children on one lesson. A fresh simulator also has no lessons in My Class, and the Sample Class only mirrors My Class's lessons.
- **The main session drives the simulators itself**, no agents: each step depends on the last, and the screenshots need to be in front of the one deciding pass/fail.
- **Never real data.** No copying a real store or backup into a simulator (children's names), no Debug launch on the Mac (it opens Danny's live notebook). The Mac look stays Danny's (Tide, Check on a device).
- **Fix scope:** layout and wording bugs, and anything else that's a few lines in `Groups/` or Today's ready section, are fixed in this session on its branch. Anything touching `ReadyGroups`, `SequenceLadder`, the loader or the record index goes to Tide (Build & fix) with the steps that show it.

## Phase 1: seed, check, fix
- Who: main session (Opus 5.5, high: judging screenshots and finding why something looks wrong takes care; a mistake in the test data costs only a redo).
- Steps:
  1. **Simulators.** Lease this checkout's own: `~/.claude/bin/sim-lease --type "iPad Pro 13-inch (M5)" --boot` and `~/.claude/bin/sim-lease --type "iPhone 17 Pro" --boot`. Attach the Simulator panel first, passing the UDID as `device:`. Build the app for the iOS simulator through `Scripts/locked_xcodebuild.sh` (building by name is fine), find the `.app` with `-showBuildSettings` (`BUILT_PRODUCTS_DIR`), install with `xcrun simctl install`. Bundle ID `DanielSDeBerry.MariasNoteBook`. If `simctl` calls hang for minutes, the simulator service is stuck again: stop and tell Danny rather than restarting it (other sessions' simulators go down with it).
  2. **Before first launch:** `xcrun simctl spawn <udid> defaults write DanielSDeBerry.MariasNoteBook EnableCloudKitSync -bool NO`. Launch once, get past onboarding, quit.
  3. **Lessons in My Class** (app not running): in the app container's `private.sqlite` (`xcrun simctl get_app_container <udid> DanielSDeBerry.MariasNoteBook data`, then find it under Library), insert 16 lessons: Math · Fractions F1–F6, Math · Geometry G1–G5, Language · Grammar W1–W5, `sortIndex` 0–15 in that order. Take the columns from the model (`CosmicDaybook.xcdatamodeld`, entity `Lesson`, class `CDLesson`). **Raise `Z_MAX` for the entity in `Z_PRIMARYKEY`** past the highest `Z_PK` inserted, or every later save fails (memory: stale-primary-key-counters).
  4. **Sample Class:** launch, switch to it ("Classroom and school year" control → Sample Class; it isn't remembered across launches), let it mirror the lessons, quit.
  5. **Ready-queue records** in the sample store (`sample-classroom.sqlite`, local only, never syncs). Model the rows on `Cosmic Daybook Tests/Planning/ReadyGroupsFixture.swift`, which builds exactly the records that make a child ready (confirmed on a presented assignment, or a proficient/mastered presentation row, with no record or plan of the next lesson). Read `AppCore/SampleClassroom/SampleClassroomSeeder+FakeRecords.swift` first so new rows don't collide with what it makes. Aim for:
     - W1 given to four children on different dates → a 4-child **W2 card** with different waits.
     - W2 given to two others → a **W3 card** where the W1 children show dashed "could join after W2".
     - F2 given to two → an **F3 card**; an unconfirmed F2 child for its **Confirm** line; a planned F3 for another child for its **"Planned with …"** line.
     - F1 given to one child → the **one-child row**, and that child dashed on the F3 card.
     - Geometry with "requires practice" on (`LessonSequenceSettings`) and an open work item on G1 for one of two G1 children → the orange **practice reason** on the G2 card.
     - One wait past the Lesson Age overdue setting (default 8 school days) → the overdue color.
     Raise `Z_MAX` for every entity inserted into.
  6. **iPad checks** (relaunch and re-select Sample Class each time):
     1. Sidebar → Planning → **Groups**: title, level picker in the toolbar, area chips with counts, 3-column grid, the one-child row expands in place.
     2. Each card: lesson name, "Area · Sequence", "k of n", names as "Maya S", waits, orange reason, dashed could-join, Confirm, "Planned with …". Nothing clipped or overlapping; no tiny text.
     3. **Plan** opens the schedule sheet with exactly the ready children ticked; after planning, they leave the card (it may become "Planned with …").
     4. **Confirm** moves that child to Ready after the page refreshes.
     5. Tap "Area · Sequence" → the **ladder**: steps, each child on their next step with tier styling, "not started"/"finished" counts, ‹ › through the area's sequences; Confirm on the ladder marks only that child (review fix 63222183).
     6. **Today**: "Ready for a next lesson" shows up to five groups in the same order, and "See all in Groups ›" opens Groups.
     7. Level picker: switching level narrows the cards and the area chips stay right.
  7. **iPhone checks:** More → Groups opens as a list (not a grid); the ladder pushes and back works; Today's link reaches Groups; tap targets usable.
  8. **Fix** what's in scope (see Decisions) on this session's branch: build iOS + Mac, run `ReadyGroupsTests`, `SequenceLadderTests`, `ReadyQueueLoaderTests`, `TodayReadyForNextCacheTests`, `TodayReadyForNextBackgroundTests`, `TodayViewModelReadyForNextTests` with `-only-testing:` and `-parallel-testing-enabled NO` on the leased iPhone 17 (`id=$(~/.claude/bin/sim-lease)`), then re-check the screen.
- Done when:
  - Every check in steps 6–7 has pass / fail / couldn't-check with a reason, and a screenshot of each screen, sent to Danny with SendUserFile.
  - In-scope bugs are fixed, built (iOS + Mac, no new warnings) with their suites green; the rest are in Tide under Build & fix with the steps that show them.
  - Tide has Danny's Mac row under Check on a device: "Open Groups on the Mac with the real class and check the grid, level picker, area chips and the ladder's ‹ ›" (add it if missing; the build session couldn't reach Tide).
  - Board rows `grp-ipad` / `grp-iphone` updated with the evidence; memory `group-planner-analysis-2026-10-02` says what was seen.
- Hand off: no (single phase).

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan.
3. Update the build board (above).
4. Run /close-out.
5. No next phase.

## Open questions
None.
