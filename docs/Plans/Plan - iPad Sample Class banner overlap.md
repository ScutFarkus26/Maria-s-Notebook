> Archived 2026-10-04: built and on main.

# iPad: Sample Class control covers "Return to My Class"

> **Done 2026-10-03** (62682481).
> In short: iPad: the class and year control no longer covers Return to My Class.
> On main; checked on the iPad Pro 13" simulator.

## Goal
On the iPad, while the Sample Class is showing, the "Return to My Class" button in the blue Sample Class banner can be seen and tapped again. The class and year control ("Sample Class · 2026–2027") stays in the top-right corner but sits just below the banner, no longer over it. Done before the next iPhone and iPad install.

## Progress
- [x] Phase 1: Move the corner control below the banners (session: here). Done 2026-10-03: iOS build passed; on the iPad Pro 13" simulator in Sample Class, Today and Students showed the banner clear and "Return to My Class" worked. The iPhone check was skipped because that code path didn't change. Seen in passing, and there before this change: on Today, the corner control (no year picker there) sits over the toolbar's "< Today" date pill.

## Decisions
- **Cause.** On the iPad (regular width, not the iPad mini), `RootView.rootLayout` (`Cosmic Daybook/AppCore/RootView/RootView.swift:269-286`) stacks `warningBanners` above `mainContent` and then lays `searchAndSyncOverlay` (classroom picker + school-year picker + search + sync dot, `RootView+Chrome.swift:58`) over the top-right corner of the *whole* stack. So the overlay lands on the first banner, and the Sample Class banner's trailing "Return to My Class" button (`ClassroomWorkspacePicker.swift:173`) sits right under it.
- **Fix: put the overlay on `mainContent` instead of on the whole stack.** With no banner the control stays exactly where it is now; with a banner it moves down with the content. One change in one place, and it also fixes the same clash for the other banners (past school year, iCloud sync warning, ephemeral store), which have trailing buttons too.
- **Ruled out:** trailing padding inside `SampleClassroomBanner` to make room (a magic number that breaks when the control's width changes, and leaves the other banners covered); hiding the overlay while Sample Class is on (removes the only way to switch years and search).
- **Untouched:** iPhone and iPad mini (`usesPhoneChrome` branch, the blue context bar with "Exit Sample") and the Mac (toolbar items, banners inside the detail column).
- No questions for Danny; the code settles the approach.

## Phase 1: Move the corner control below the banners
- Who: main session (Opus 5.5, low effort; one small edit in one file plus a simulator look).
- Steps:
  1. In `Cosmic Daybook/AppCore/RootView/RootView.swift` `rootLayout` (iOS branch), apply `.overlay(alignment: .topTrailing) { searchAndSyncOverlay }` to `mainContent` inside the `VStack` when `!usesPhoneChrome`, and drop the overlay from the outer stack. Keep the `Divider()` above the content; update the comment to say why the overlay rides on the content, not the stack.
  2. Build the iOS app through `Scripts/locked_xcodebuild.sh`.
  3. iPad simulator (`~/.claude/bin/sim-lease --type "iPad Pro 13-inch (M5)"` or the nearest iPad), open the Simulator panel with that UDID, switch to Sample Class from the corner menu.
- Done when:
  - The iOS build succeeds.
  - On the iPad simulator in Sample Class: the banner's "Return to My Class" is fully visible, tapping it returns to My Class, and the "Sample Class · 2026–2027" control sits below the banner at the top right without covering page content's own top-right buttons (check Today and one other tab, e.g. Students). Screenshot sent to Danny.
  - Back in My Class with no banner, the corner control is in the same spot as before (compare to a screenshot from `main`, or eyeball against the Groups sim-check shots).
  - iPhone simulator: one glance that the blue context bar and "Exit Sample" are unchanged.
  - No unit tests cover this layout; none to run.
- Hand off: no.

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan.
3. Update the build board, if the plan lists one.
4. Run /close-out.
5. If the next phase is a fresh session, print its starter prompt: "Model: <from its Who line>" on the first line, then "In <project folder>, read <this file> and do Phase <N>. Follow its Ending a phase steps when done."

## Open questions
None.
