# Notebook: the attendance roll idle on a past day (measured 2026-10-10)

The notebook's half of the Daybook Assistant's finding 1 (see [the Assistant's baseline](<2026-10-07-assistant-idle-baseline.md>), "After the fixes"). The roll band's buttons (`AttendanceExpandedView+Band.swift`) and the front-desk control (`AttendanceExpandedView+FrontDesk.swift`) sat in `TimelineView(.explicit(frontDeskChangeTimes))`. Once both of its times have passed (every day after the due time, and every past day), an explicit timeline redraws its content every frame. They now sit in `RedrawsAt(times:)`, which sleeps to each time still ahead and then waits for nothing.

## How it was measured

- **Builds:** Release builds of the `Cosmic Daybook` scheme for the iOS simulator: before from main f68a1540, after from the same commit plus the fix.
- **Simulator:** this checkout's leased iPad Air 11-inch (M4), iOS 27.0, signed out of iCloud. The iPad, because the roll band shows only on iPad and Mac.
- **Data:** the Sample Class, switched to through the classroom picker. My Class on that simulator is empty.
- **The day:** a Saturday, so Today and the Attendance tab both showed Friday 9 Oct, a past day. A school day's "today after the due time" wasn't reachable: it would have needed a 19-hour clock shift. The Assistant measured that case (7–10.5% → 0.0%). The two are the same mechanism: every time in the timeline has passed.
- **Driving:** a throwaway XCUITest attached by bundle ID tapped the screens into place and then ended, so nothing was driving the app while it was measured. The simulator panel wasn't available.
- **CPU:** `top -l 2 -s 60 -pid <pid> -stats pid,cpu,idlew,power,time`, taking the second sample (the average over 60 s). Also `sample <pid> 5` and `footprint <pid>`.
- **The Mac was very busy:** other sessions' builds and tests kept the load average between 120 and 540 throughout. A per-frame redraw starved of CPU shows less than it would on a quiet Mac, so the before-numbers are, if anything, low.
- **The Mac app wasn't measured.** The copy running was Danny's TestFlight copy, opened by the MCP bridge, and a second copy can't safely open the live store. The Mac draws the same band with the same code.

## Idle on screen, 60 s

| Screen (Sample Class, Friday 9 Oct, all 9 marked) | Before | After |
|---|---|---|
| Today, roll collapsed (no band: the control) | 0.0% | — |
| Today, roll expanded (band with Email Front Desk) | **6.3%** | **0.0%** |
| Attendance tab (band, tiles, Insights) | **9.4%** | **0.0%** |

Idle wake-ups: 0 in every sample. Footprint on the Attendance tab: 88 MB before, 91 MB after (a fresh launch each time, so the sizes don't compare).

## What the samples showed

- **Before (Today, expanded):** about 10% of the main thread's samples (370 of 3,838) were in run-loop work driven by SwiftUI's display link: `ViewGraphDisplayLink.displayLinkTimer` → `ViewGraphRootValueUpdater.render`, with no app code below `main`.
- **After:** no `displayLinkTimer` frames at all, and the main thread sat in `mach_msg` the whole time.

The screens looked the same before and after: the same band, the same Email Front Desk button.
