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
