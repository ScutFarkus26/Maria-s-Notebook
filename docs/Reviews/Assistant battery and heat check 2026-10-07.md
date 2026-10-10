# Assistant battery and heat check

> Phase 1 of [Plan - Assistant battery and heat check](<../Plans/Plan - Assistant battery and heat check.md>), done 2026-10-10. Three read-only code checkers (background and sync on Opus; on-screen and launch/memory on Sonnet), the lead re-reading the top findings, and measurements on a Release build. The numbers are in [the baseline](<../Technical notes/Performance baselines/2026-10-07-assistant-idle-baseline.md>). Nothing in the app was changed.

## The short answer

**Probably not the Assistant on its own, but it isn't free.** Three findings support that.

- **While closed, it goes quiet fast.** On the simulator it did about a second of work after she left it, then nothing. From the code, each cloud wake keeps it up about 1–3 seconds. A normal school day might bring 10–40 wakes. That's a minute or two of background time a day plus some radio, not enough to empty a battery.
- **While open, the attendance grid never rests.** It redraws every frame even when nothing changes, at 5–8% CPU on the simulator against 0.1% on the weekend screen. On a phone that means extra drain and warmth for as long as the grid is on screen. A phone with a fast screen may also stay at its highest refresh rate. If she keeps the Assistant open through the morning, this is the one finding that could matter.
- **Nothing keeps her screen awake.** The app never turns off auto-lock, and has no repeating timers or endless animations in its own code.

**What settles it** is her battery screenshot ([Tide row](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Ask%20the%20assistant%20whose%20battery%20died%20for%20a%20screenshot%20of%20her%20phone%27s%20battery%20use%20by%20app)). Her iPhone ran iOS 18.6 on 29 September. iOS 18 shows each app's share of battery use and the screen-on and screen-off times, but not a separate "Background" line. If the Assistant is a small share, the drain was something else, and the list below is upkeep. If it's large and on screen, finding 1 is the cause. If it's large in the background, findings 2–7 are.

## While closed

- **Wakes per school day:** about 10–40, a static estimate. Another assistant's marks make about 50 changes to the class share each, since every mark is a save plus an attach. The guide's pickups, notes and fixes add 10–25, and Restock 0–10. CloudKit bundles these together and iOS rations quiet pushes, so the real count is uncertain.
- **Cost per wake:** about 1–3 s awake past the import itself, 50–150 ms of CPU, about 20 small fetches, and **30–60 reminder requests added again** (findings 2 and 3).
- **Measured on the simulator:** after leaving the grid, about 1 s of CPU in the first 10 s, then 0.0% for the next 60 s.
- **No loops:** nothing that handles a change writes back to either store. Wakes don't set off more wakes.
- **Longer holds:** the app can stay awake past its limit when she leaves it offline right after a mark, and Siri commands can do the same (finding 6).

## Findings

Each finding is marked **safe** (same behavior, cheaper) or **behavior** (your call), with a rough size: XS is a line or two, S an afternoon or less, M a day.

### Biggest first

1. **The attendance grid redraws every frame while idle.** Measured at 7.7–8.3% CPU on Friday's grid in the Release build, and 5–6% after leaving and coming back. The weekend screen sits at 0.1% and Restock at 1.0%.
   - The Release and Debug samples both show SwiftUI's display link running every frame, with no app code in them. An animation inside SwiftUI never finishes.
   - Ruled out: the confetti's frame-by-frame timeline (it only runs while confetti falls), the two once-a-minute clocks, the backdrop (plain behind a past day), the tile animations (they only run when triggered), and the day-change slide (it persists without one).
   - Left to suspect: the grid's fade mask over the scroll view, the arrival bar's fill line and its animations, and the glass controls.
   - **Safe.** S–M: find it in a test build by removing those one at a time, then fix it.
   - Unverified: whether "today's" grid does the same (it was Saturday), and what it costs on a phone. [Check on a phone](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=On%20a%20school%20day%2C%20leave%20the%20Daybook%20Assistant%27s%20attendance%20grid%20open%20on%20an%20iPhone%20for%2010%20minutes%20and%20feel%20whether%20the%20phone%20gets%20warm).
2. **Every reminder rebuild re-adds all arrival and front-desk reminders, even unchanged ones.** `FrontDeskEmailReminder.swift:250-267` (`ReminderRuns.replace`). Pickup reminders already compare first (`EarlyPickupReminder.swift:168-175`). That's about 30 requests per rebuild, at 100–300 rebuilds a day. **Safe.** S: compare first, as pickups do.
3. **Each change rebuilds the reminders twice, and queued rebuilds that are already stale still run.**
   - Both the background upkeep (`AssistantBootstrapper+Observers.swift:26` → `EarlyPickupReminderUpkeep.swift:29-36`) and the screen's follower (`ArrivalReminder.swift:196-199`) rebuild, and every screen reload sets the follower off again.
   - `ReminderRuns.run` (`FrontDeskEmailReminder.swift:237-245`) finishes every queued rebuild, even when a newer one replaces it. Marking 22 children makes about 22 rebuilds in a row.
   - **Safe.** S–M: send the follower through the upkeep's one-second settle, and run only the newest queued rebuild.
4. **The screens reload after every sync, even while the app is in the background.**
   - `RemoteImportReloader` (`RemoteImportReloader.swift:56-76`) feeds both the attendance screen and Restock (`AssistantTabs.swift:35-40`).
   - Attendance runs about 12–15 fetches. One of them is a 40-day read of about 300 records, needed only for the "welcome back" wave.
   - Restock runs its full load. That includes a reconcile that can save, and it always bumps `revision`, which redraws every Restock tile.
   - Failed or empty imports count too, because `isFinishedImport` doesn't check for success.
   - **Safe:** pause the reloader while the app isn't on screen (the `isPaused` hold is already there, and the return-to-app reload already exists), and bump `revision` only on a real change. **Behavior:** whether Restock's reconcile should run after a sync at all. S.
5. **The sync-change handler doesn't check which store changed or wait for a burst to settle.** `AssistantBootstrapper+Observers.swift:19-47`. Each notification, including her own saves, runs a membership fetch and the still-in-class check, and starts a new background task (`EarlyPickupReminderUpkeep.swift:32`). **Safe.** S: one background task per settle window, and the share check only for changes from someone else.
6. **Some waits that hold the app awake have no time limit.**
   - When she leaves the app with unsent marks, the keep-alive's wait for the share attach (`UnsentChangesKeepAlive.swift:164-171` → `AssistantShareAttacher.swift:196-198`) can run past its 25 s limit, up to iOS's own cut-off. iOS counts those against the app when it decides how often to wake it.
   - Siri's attach wait has the same gap (`AssistantSiriHost.swift:95`).
   - **Safe.** S: race each wait against its deadline.

### Smaller

7. **A background relaunch runs the whole startup.** When iOS has closed the app, a push restarts it and runs the full start (`AssistantApp.swift:25-27` → `AssistantBootstrapper.swift:115-127`). That's both stores and both mirrors, the account checks, the name-zone lookup, the share retry and the history-trim timer. **Safe.** M: open the stores only, and leave the rest for when she opens the app.
8. **The stores open on the main thread at every cold start, Siri's included.** `AssistantStack.swift:30`. The notebook moved this off the main thread on 5 October; the Assistant didn't. **Safe.** M. The risk is iOS killing a slow background launch, not steady drain.
9. **The notebook's launch repairs run in the Assistant at every start.** These are a primary-key check over the whole ~100-entity model plus two smaller checks (`CoreDataStack+SchemaVersion.swift:171`). **Behavior:** they're safety nets built for your notebook's store. S.
10. **A second iCloud mirror holds one row.** The Assistant's private store, mirrored to its own iCloud database, holds only her membership row (`CoreDataStack+Stores.swift:156-157`). It costs a second subscription and its own wakes. It was also left open on 29 September. **Behavior.** M.
11. **Siri's name lists are registered again at every launch.** The "already registered" check lives only in memory (`AssistantAppShortcuts.swift:110,126`). **Safe.** S: keep a hash of the names.
12. **The name write runs on every return to the app, even with nothing waiting** (`AssistantBootstrapper+Names.swift:98-115`). **Behavior:** the duplicate fold rides along with it. S.
13. **The guide's name is formatted again for each of 22 tiles on every pass** (`AssistantAttendanceView.swift:407-411`). **Safe.** XS.
14. **The sample class's database stays open after she joins the real class**, a few MB (`AssistantSampleClass.swift:65`). **Safe.** XS.
15. **The iCloud account status is asked twice at launch** (`AssistantBootstrapper+Names.swift:35`, `AssistantApp.swift:49`). **Safe.** XS; negligible.
16. **The grid's fade mask over frosted tiles costs an extra drawing pass on every frame of scrolling or tapping** (`AssistantAttendanceView.swift:307`). Zero at rest. Unverified: it needs a look on a device. Tied to finding 1.

## Checked and fine

- **Nothing keeps it busy on its own:** no `isIdleTimerDisabled`, `repeatForever`, `Timer` or `CADisplayLink` in its own code. The arrival bar and front-desk timers are one-shot sleeps until the next due time, and the clocks tick once a minute.
- **Housekeeping is rare:** the history trim runs once per launch, at most every 60 days. The share retry backs off from 1 to 10 minutes and doesn't run while the app is suspended. Pickup reminders compare before writing.
- **The data is small and the fetches are scoped:** only about a dozen small shared tables reach the Assistant, and every fetch is limited by date or row count.
- **No runaway caches, and memory is low:** 37–44 MB measured.
- **The wallpaper photo is already shrunk on import,** as Apple advises. Only the import itself briefly holds the full original.
- **Marking and stepping days are cheap:** 9 queries per mark, 20 per day step.

## Not measured, and why

- **Real heat and battery:** you chose simulator only. If her screenshot points at the Assistant, the follow-up is a Power Profiler recording on your own iPhone with the TestFlight build (see the plan's Apple guidance).
- **A real sync wake:** a simulator signed out of iCloud gets no pushes, so the cost per wake comes from reading the code.
- **Today's grid:** the check ran on a Saturday.
