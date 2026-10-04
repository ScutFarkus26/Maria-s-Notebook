# Daybook Assistant: the attendance grid redrew when nothing had changed (2026-09-29)

## How it was measured

A Debug build of the Daybook Assistant on the iPhone SE (3rd generation) simulator, iOS 27.0
(the assistant's own iPhone runs iOS 18.6, so absolute counts there may differ), launched with
`-AssistantSampleClass` (in-memory store, no iCloud). A temporary probe, never committed, counted
`AssistantAttendanceTile.body` and `AssistantAttendanceView.body` passes and printed
`_printChanges()`. One "trip" = open Settings, wait 2.5 s, reopen the Assistant, wait 2.5 s
(`simctl launch`), five trips per run.

## Per trip away and back, on main's grid (175b8fce: 22 children, all on screen)

| Cause | Before | After |
|---|---|---|
| The return's reload wrote back identical rows (`rows` changed) | 22 tile draws, 1 screen pass | 0 |
| Scene phase, 4 changes per trip, read in the screen's `body` | 88 tile draws, 4 screen passes | 0 |
| **Total** | **110 tile draws, 5 screen passes** | **0** |

The reload itself still runs on every return (0.3–0.5 ms here) and still redraws when it finds a
change: a tap logs `rows changed` and one pass over the grid.

The same `rows` fix covers the other frequent reload: every finished CloudKit import into the
shared store reloads the day (`RemoteImportReloader`, 1 s debounce), and most imports touch other
days or other children's records, so they now cost the fetches and no redraw.

First measured on the grid before 96abff0a/175b8fce (16 children, 14 on screen): 98 tile draws and
5 screen passes per trip, 0 after. 28 of those came from the tile reading `colorScheme` in `body`,
which redrew it for iOS's light and dark app-switcher snapshots; a draw-time `ShapeStyle` fixed
that, and it was dropped on rebase because 175b8fce's tile no longer reads `colorScheme`.

## Fixes

1. `AssistantAttendanceViewModel.Row` is `Equatable`, with the student's name copied in. The
   `@Observable` macro (Swift 6.2+) skips notifying when an `Equatable` property is set to an equal
   value; `Row` was not `Equatable`, so every reload announced `rows`.
2. `AssistantReloadOnReturn`, a `ViewModifier`, owns `@Environment(\.scenePhase)` and the
   follows-today flag (and clears the Late undo line on leaving the foreground, through a
   callback), so a phase change re-evaluates only the modifier.
3. (Not a redraw) `CDAttendanceStore.attachNewRecordsToClassroomShare` reads the shares off the main
   actor (`ClassroomShareAttach.shares(inStoreWithIdentifier:container:)`, `@concurrent`). It ran
   `container.fetchShares(in:)` on the main thread after every save that created a mark (the first
   mark of each child each day, and the switch to Late). Static count, 1 → 0 main-thread reads per such
   save; no simulator here has a CloudKit share to time it against.

## Also seen, left alone

- Switching to Late took 22 ms on the simulator for 16 children (in memory, including the save and
  reload): `CDAttendanceStore.markUnmarkedAbsent` fetches the day's records and counts its locks once
  per child. Once a morning; a hitch, not heat.
- The import reloader keeps reloading while the app is in the background (a push wakes it). After fix
  1 that is the fetches only, about half a millisecond here.
