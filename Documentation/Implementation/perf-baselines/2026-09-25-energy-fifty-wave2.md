# Energy Fifty, wave two (2026-09-25)

Wave two of the Energy Fifty audit (private artifact "Daybook Energy Fifty"; wave one and the
baseline are in `2026-09-25-energy-fifty-wave1.md`): the Mac process items plus the EventKit,
backup and activation fixes. Five agents worked in parallel worktrees off 32dfd35e. The merged
branch passed an iOS build-for-testing, a macOS build, a Daybook Assistant build and the full iOS
suite on the iPhone 17 simulator together before landing.

Nothing here could be measured on the running Mac app (agents may not launch it against the
live store), so the numbers are static counts or unit tests, as marked.

| # | Change | Before → after | How measured |
|---|---|---|---|
| 2 | MCP bridge checks for a running copy, a stopped listener and the enabled marker before `open` | extra launches when a copy runs / the toggle is off / a stopped copy holds the port: 1 → 0 | `Scripts/mcp/test-cosmic-daybook-mcp.sh` (old script 16/25 checks, new 25/25), `MCPEnabledMarkerTests` |
| 3 | MCP-only launch: no window, quits ~10 min after the last Claude connection and window close | UI for a bridge launch: full main window → none; lifetime: unbounded → ~10 min idle | `AppLaunchModeTests`, `MCPIdleQuitPolicyTests` |
| 4 | Desktop companion brings the open main window forward | main windows created per companion action (one open): 1 → 0 | `MainWindowCandidateTests` |
| 6 | App-wide services start once per process; Spotlight pass deferred and hashed off main | service start-ups per extra window: 7 → 0; leaked account listeners per reconfigure: 1 → 0 | `AppServicesStartGateTests`, `CloudKitHealthCheckListenerTests` |
| 7 | Visibility gates also watch Mac window occlusion | reloads per save burst while minimized/covered: 1–2 per screen → 0, one catch-up on return; typing-indicator wakes ~2.9/s → 0 | `WhenVisibleGateTests`, `WindowVisibilityTrackerTests` |
| 8 | Companion hides with the app (`canHide`), its counts reload only while visible | companion reloads per import while hidden: 1 → 0 | static |
| 9 | EventKit mirrors write only new or changed rows | rows written per idle sync (65-row test): 65 → 0 | `EventKitMirrorEventTests`, `EventKitMirrorReminderTests` |
| 10 | Backup encode/encrypt/verify and decode are `@concurrent`; automatic triggers at `.utility` | main-thread phases: 74/74 → 0/74 (encode), 1/1 → 0/1 (decode) | `BackupPipelineThreadingTests` |
| 11 | EventKit bursts debounced 3 s; throttle only after a real sync; lazy stores; missing Reminders list pauses observation | attempts per burst 2 → 1; retries/day with the list missing ~39 → 0 after one per launch | `EventKitChangeObserverTests`, `EventKitSyncThrottleTests`, `ReminderChangeListeningTests` |
| 15 | Mac interval backup scheduled by `NSBackgroundActivityScheduler` (10% tolerance, `.utility`) | exact wake → system-chosen ±10% window | `ScheduledBackupTimingTests` |
| 16 | Activation work only when the day, school calendar or counter epoch changed | per activation with no change: 8 counts + a full fetch + album checks → 0 | `CalendarDayActivationGateTests` |
| 18 | Overnight iPad backup: charger required, completes once, stops between entity types on expiry | `setTaskCompleted` on expiry 2 → 1; cancellation checks 0 → 76 | `BackgroundBackupStopTests` |
| 48 | Daybook Assistant no longer runs the persistent-history processor | history fetches per remote-change burst in the Assistant: 1–2 → 0 | static + Assistant build |
| 50 | Command bar stops dictation when it closes | microphone/speech task left running after cancel: 1 → 0 | static |

## Not done, or needing Danny

- 49 (remove the Assistant's remote-notification background mode): Apple's Core Data + CloudKit
  docs say that mode is how the container gets its silent pushes, so removing it could stop
  changes reaching the Assistant while it is open. Left unchanged pending a device test or a new
  decision.
- 9: reminders' dates are compared exactly; CloudKit keeps milliseconds, so if both devices sync
  the same Reminders list, reminders with sub-millisecond dates can still be rewritten by the
  other device. Comparing to the millisecond would stop that (Danny's call).
- 11: beyond the decision, a later successful sync also resumes observation (so a list hidden
  for a moment doesn't leave change-driven sync off until Settings is touched).
- 16: on the iPad, while Albums is a hidden tab, the album library isn't refreshed on
  activation, so chat's album search won't see an album edited outside the app until Albums is
  opened.
- 2/3: until the new build has run once (normally) with Claude access on, there is no
  `~/.cosmic-daybook/enabled` marker, so Claude sessions won't autolaunch the app. The one-time
  LaunchServices cleanup of dead DerivedData registrations is Danny's to run.
- Noticed, not changed: `OpenWindowOnNotificationModifier` is on every main window, so with N
  main windows one "open Keyboard Shortcuts" notification opens N windows.
