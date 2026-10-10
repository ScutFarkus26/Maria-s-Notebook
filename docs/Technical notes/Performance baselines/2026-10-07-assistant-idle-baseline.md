# Daybook Assistant: idle, background and per-action cost (measured 2026-10-10)

Part of [Plan - Assistant battery and heat check](<../../Plans/Plan - Assistant battery and heat check.md>). The findings are in [Assistant battery and heat check 2026-10-07](<../../Reviews/Assistant battery and heat check 2026-10-07.md>).

## How it was measured

- **Build:** a Release build of the `Daybook Assistant` scheme from `f90d6fdb` (main 05826331 merged in).
- **Simulator:** the checkout's leased iPhone 17 simulator, iOS 27.0, signed out of iCloud.
- **Launch:** no launch flags. "Try a Sample Class" on the join screen took the full start path, with the observers, reminder upkeep and keep-alives running.
- **The day:** a Saturday, so the grid was measured on Friday 9 Oct (stepped back one day). There are no "today" grid numbers.
- **CPU:** `top -l 2 -s <n> -pid <pid> -stats pid,cpu,idlew,power,mem`, taking the second sample (the average over the interval).
- **Memory:** `footprint <pid>`.
- **Queries:** the `-com.apple.CoreData.SQLDebug 1` launch argument, with `SELECT` lines counted before and after each action.
- **What the numbers mean:** these are Mac-side numbers for the simulator process. They compare screens and actions with each other. They are not phone battery figures and say nothing about the radio, the display or CloudKit pushes.

Setup snag: on the first boot, the simulator's notification service had lost its connections to the simulator's own system services. `pendingNotificationRequests()` never returned, so the app sat on "Starting…". `simctl erase` of the leased simulator fixed it. This was a simulator fault, not the app: that call has run at startup since 3548d94f (1 Oct), and assistants have opened the app since then.

## Idle on screen

| Screen | CPU | Idle wake-ups | Notes |
|---|---|---|---|
| Attendance grid, Friday, 22 tiles | **7.7%** (60 s), 8.3% (15 s), 5.3–5.9% after a trip out and back | 0 | SwiftUI's display link runs every frame, with no app code in the samples (Release and Debug) |
| Weekend screen (Saturday) | 0.1% (20 s) | 0 | |
| Restock tab | 1.0% (20 s, steady) | 0 | |

## While closed

After leaving the grid for Settings, measured in 10 s steps: 8.9% in the first 10 s (about 1 s of CPU), then **0.0%** for the next 60 s. The app stopped working within 10 s. No pushes reach a simulator that's signed out of iCloud, so the cost of a background wake comes from reading the code: about 1–3 s awake and 50–150 ms of CPU per wake (see the report).

## Memory

| Moment | `phys_footprint` |
|---|---|
| Grid open, idle | 41 MB (peak 41 MB) |
| Weekend screen | 37 MB |
| Restock tab open | 44 MB |

The wallpaper photo and tab trips were not measured. Reading the code puts a photo wallpaper at about 4 MB decoded after import.

## Queries per action

| Action | SELECTs |
|---|---|
| First step back after relaunch (includes opening the sample's stores and mirroring tables) | 211 |
| One day step (Thursday from Friday) | 20 (5 attendance, 4 non-school day, 2 student, 2 overrides, 2 membership, 2 day lock, 3 others) |
| One mark (tap a tile) | 9 (writes were not counted per action) |

## After the fixes (2026-10-10, Phase 3)

Findings 1–6 fixed (see the report). Same simulator, iOS 27.0, signed out of iCloud, Saturday again.

- **Builds:** the grid numbers come from Agent G's Release build (main f567d9b8 plus the grid fix 4464eb59), measured the same way as above. Everything else comes from a Release build of the merged branch (all three agents' work plus 3a0500f1).
- **Launch:** the sample class reopened by setting its "was open" preference (`Assistant.sampleClass.wasOpen`) and relaunching. That takes the same start path as tapping "Try a Sample Class". Simulator taps weren't available to this session, so the grid page, Restock and the per-mark queries weren't re-taken on the merged build.

### Idle on screen

| Screen | Before | After |
|---|---|---|
| Attendance grid, a past day (Friday) | 7.7% (60 s); 9.4% in Agent G's own before-run | **0.6%** (60 s, Agent G) |
| Attendance grid, "today" on a school day after the due time | not measured (Saturday) | **0.0%** (from 7.0–10.5%; Agent G moved the app's time zone so Saturday morning was Friday night) |
| Weekend screen | 0.1% (20 s) | 0.0% (20 s, merged build) |

### While closed

Left the weekend screen for Settings at 09:12:40. The last "Update reminders" background task ended 2.0 s later, and iOS suspended the app at 2.1 s. CPU: 1.6% in the first 10 s, then 0.0% for the next 30 s. Before: work stopped within 10 s.

Setup snag, again: on the first launch after `simctl erase`, the app sat on "Starting…". Its first `pendingNotificationRequests()` never returned, so the launch reminder rebuild held its background task until iOS cut it off at about 30 s. An uninstall and reinstall cleared it for both the merged build and Agent G's, and nothing in that path changed. It's the same simulator fault as in Phase 1.

### Memory

| Moment | Before | After |
|---|---|---|
| Weekend screen | 37 MB | 27–28 MB (merged build; not attributable to the fixes alone: a fresh install with no sample marks yet) |

### Counted from the code and tests (no pushes reach the simulator)

| What | Before | After |
|---|---|---|
| Reminder requests added in a rebuild with nothing changed | ~30 | 0 |
| Reminder rebuilds per change | 2 (screen + upkeep), ~22 for 22 marks in a row | 1 per one-second settle window |
| Background tasks per burst of remote changes | 1 per notification | 1 per settle window |
| Membership reads per change | every change, her own saves included | private-store changes only |
| Reloads per finished import while the app is away | attendance (~12–15 fetches) + full Restock load | none; one load on return |
| Longest attach wait when leaving or after Siri | until iOS's cut-off (~30 s) | 25 s, export wait included |
