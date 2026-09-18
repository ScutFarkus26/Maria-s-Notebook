# Measuring before and after

An efficiency change without a number attached is a guess. Pick the cheapest measurement
that can actually move for the change you are making, take it before, take it after, and
write both into the PR or commit message. Keep durable baselines in
`Documentation/Implementation/perf-baselines/` (one dated file per capture).

## Which instrument for which symptom

| Symptom | First measurement | Tool |
|---|---|---|
| Heat / battery while the app sits idle | CPU % over 60 s idle, and what wakes it | Instruments **Power Profiler** (Xcode 26+; on-device), or Time Profiler with "Record Waiting Threads" off; `top -pid` on the Mac |
| Heat during sync | count of body evaluations and fetches per remote-change burst | Instruments **SwiftUI** template (View Body / Update Groups) + **Data Persistence** template |
| Memory growth | `phys_footprint` before/after the flow, allocations by category | Instruments **Allocations** (Generations / mark heap), `MemoryPressureMonitor` log lines already print footprint |
| Slow launch | signpost intervals in category `Launch` | `log stream --signpost` (recipe below) or Instruments **App Launch** |
| Jank / hangs | main-thread intervals > 250 ms | Instruments **Hangs** + **Time Profiler**; Xcode Organizer → Hangs on TestFlight builds |
| Too many fetches | SQL statements per action | launch argument `-com.apple.CoreData.SQLDebug 1` (3 for bind values), or the Instruments Data Persistence template |
| Something wakes too often | timer / dispatch wakeups | Instruments **Time Profiler** with the *System Load* / *Points of Interest* tracks, `powermetrics --samplers tasks` on the Mac (needs sudo; ask Danny) |

## Recipes

A populated store without the live data: switch the app to the **Sample Class** workspace
(`ClassroomWorkspaceStore` → `SampleClassroomSeeder.prepare`), which builds students,
attendance, lesson activity and notes in an isolated store on any simulator. Measure there
when the production store is unavailable, and say so in the write-up; the sample class is
smaller than Danny's real one, so absolute numbers do not compare.

Launch signposts on the Mac with the real store:

```bash
log stream --level debug --signpost --style compact \
  --predicate 'subsystem == "DanielSDeBerry.MariasNoteBook" AND category == "Launch"'
```

then `open -a "Cosmic Daybook"` in a second terminal. Compare against
`perf-baselines/2026-09-04-launch-signposts.md`.

Record a trace from the command line (Xcode 27 fixed `xctrace record` on simulators; the Mac app with the real store is still the more honest target). Add `--instrument 'Thermal State'` to any template to see thermal transitions alongside it:

```bash
xctrace record --template 'Time Profiler' --attach "Cosmic Daybook" --time-limit 60s \
  --output "$TMPDIR/idle-before.trace"
xctrace export --input "$TMPDIR/idle-before.trace" --toc
```

Templates worth knowing by name: `Time Profiler`, `Allocations`, `Leaks`, `SwiftUI`,
`Data Persistence` (Core Data + SQLite, the "Core Data" template of older Xcodes), `Swift Concurrency` (task and actor contention), `App Launch`, `Animation Hitches`, `Power Profiler` (device only; Xcode 27.0 lists all of these). `xctrace list templates` prints the exact names installed.

Core Data SQL log for one action (simulator):

```bash
xcrun simctl launch --console-pty <UDID> DanielSDeBerry.MariasNoteBook \
  -com.apple.CoreData.SQLDebug 1 2>&1 | grep -c "SELECT"
```

Memory footprint from inside the process: `MemoryPressureMonitor` already logs it at each
pressure event; for a before/after, log `currentMemoryFootprintMB()` (private in that file;
expose a debug helper rather than duplicating the `task_vm_info` call).

Simulating bad conditions without waiting for them:
- Thermal state: Xcode → Window → Devices and Simulators → select device → **Device
  Conditions** → Thermal State (Fair / Serious / Critical). `EnergyPolicy` reacts to the
  notification, so maintenance should visibly pause in the log
  (`Background maintenance deferring: thermal=serious`).
- Low Power Mode: Settings on the device or the simulator's Features menu (iOS 26+).
- Memory pressure: Simulator → Debug → Simulate Memory Warning.
- Slow / expensive network: Device Conditions → Network Link.

## Clean-build and type-check cost (for compile-time regressions)

```bash
xcodebuild -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  -derivedDataPath "$TMPDIR/dd-clean" -showBuildTimingSummary clean build
```

Compare against `perf-baselines/2026-09-04-clean-build.md`. The per-file 100 ms warning is
only meaningful on a clean build on both sides.

## What to write down

Before/after numbers, the exact command or Instruments template, device or simulator,
Debug vs Release, and whether the store was empty or the production copy. A number without
that context cannot be compared next month.
