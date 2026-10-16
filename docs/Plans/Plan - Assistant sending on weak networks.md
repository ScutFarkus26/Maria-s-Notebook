# Assistant sending on weak networks (2026-10-16)

> **Not started.** Written 2026-10-16 from an investigation on branch `claude/assistants-attendance-upload-921752`.
> In short: the Assistant's marks sometimes sit on her phone for minutes, because nothing notices the network coming back, locking the phone doesn't retry waiting marks, and a weak link stalls sending; five fixes make it retry at the right moments and say plainly when it's offline.

## Why marks don't always go live

An assistant's mark reaches the guide in two steps:

1. **Saved on her phone** (`AssistantSave.save`), into the shared store.
2. **Put into the classroom share** by the app itself (`AssistantShareAttacher` → `CDAttendanceStore.attachNewRecordsToClassroomShare` → `ClassroomShareAttach.attach` → `container.share(_:to:)`). Until this step succeeds the guide never sees the mark.

Step 2 is the weak point. Unlike an ordinary Core Data save, which CloudKit sends in its own time and retries by itself, `share(_:to:)` needs a live round trip to iCloud **while the app is running**, and the app decides when to try. Today it tries:

- right after each save (the new mark only, plus the backlog if it isn't resting);
- when a failed pass's rest ends: 1, 2, 4, 8, then 10 minutes (`AssistantShareAttacher.rest(afterFailures:)`), but only while the app is awake;
- when she brings the app back to the front (`willEnterForegroundNotification`);
- at a cold launch (`AssistantBootstrapper.refreshMembership`), including one started by a sync push;
- when the iCloud hold lifts (`AssistantFilingHold.onLift`).

What goes wrong on a weak or changing network:

- **Nothing notices the network coming back.** No `NWPathMonitor` anywhere in the Assistant. Wi-Fi drops while she walks out to the car line, her marks fail, the pass rests for a minute or more, and when the phone rejoins Wi-Fi or switches to cellular nothing happens until the rest ends, she taps again, or she reopens the app.
- **Locking the phone doesn't retry waiting marks.** On leaving the foreground, `UnsentChangesKeepAlive` keeps the app awake (up to 25 s) only if a pass is running right now or a save hasn't been exported. Marks resting after a failure count as neither, so the app is suspended with them still waiting, and they aren't tried in those 25 s.
- **Nothing retries while the phone sleeps.** The rest timer is a `Task.sleep`, which freezes with the app. A sync push that wakes an already-running (suspended) app doesn't retry either: only a cold launch flushes. So a mark that failed just before she locked the phone waits until she opens the app again.
- **A weak link stalls the whole queue.** One pass at a time. Each chunk first fetches the share's latest copy from the server (`ClassroomShareAttach.current`, default CloudKit timeouts, about 60 s with no answer), then calls `share(_:to:)`. When a chunk fails with a network error, the pass retries **each mark on its own**, each with its own fetch and call, instead of stopping. On a weak link one pass can take minutes, and marks tapped meanwhile wait behind it.
- **The sync line hides it.** "Not sent yet. They'll go when you're back online." shows only when CloudKit's own export failed. When the share step fails for lack of network, the line says "Sending to iCloud…" indefinitely, so she can't tell her marks are stuck.

Settings on her phone can cause the same symptom and are worth checking before blaming the code: Settings › Cellular › Daybook Assistant switched off (nothing goes on cellular), Low Data Mode, Low Power Mode, and Background App Refresh off (no push wakes).

## The fixes

### Fix 1: retry when the network comes back or changes

- New file `Daybook Assistant/Sync/AssistantNetworkWatch.swift`: one `NWPathMonitor` on a utility queue, started in `AssistantStack.shared()` beside the keep-alive (not for the sample class), dropped with the stack.
- When the path goes from unsatisfied to satisfied, or stays satisfied but changes interface (Wi-Fi ↔ cellular), wait about 3 s for the link to settle, then call `AssistantShareAttacher.shared.retryWaiting()` on the main actor. Repeated changes within the settle time collapse into one retry.
- The decision is a pure static function (`shouldRetry(from:to:)` over a small value type: satisfied, interface kind), so it's testable without a real monitor.
- Event-driven and cheap: no polling. It only runs while the app runs, which is fine: that's the only time `share(_:to:)` can run anyway.

### Fix 2: locking the phone tries the waiting marks

- `UnsentChangesKeepAlive` (shared with the notebook, which compiles it too) gains one more closure, `hasWaitingWork: @MainActor () -> Bool`, default `{ false }`, so the notebook's behavior doesn't change. `didLeaveForeground` keeps the app awake when `hasUnsentWork || hasWaitingWork()`.
- `hasUnsentWork` itself stays as it is: Leave reads it (`AssistantBootstrapper.unsentMarks`) and already counts waiting marks separately.
- In `AssistantStack.shared()`: `hasWaitingWork: { AssistantShareAttacher.shared.pendingCount > 0 }`, and `waitForWork` becomes "`retryWaiting()`, then `waitUntilIdle()`", so the waiting marks get a real try, rest or no rest, inside the same 25 s limit. The limit and the race against a hung `share(_:to:)` stay.
- Siri's path is untouched: it waits with `UnsentChangesKeepAlive.wait(atMost:for:)` and its own closure.

### Fix 3: a network failure stops the pass, and the share fetch gives up sooner

In `Cosmic Daybook/Sharing/ClassroomShareAttach.swift` (shared by both apps):

- New `static func indicatesNoConnection(_ error: NSError) -> Bool`: true when the error, or any underlying or partial-failure error inside it, is CloudKit's `networkUnavailable`, `networkFailure` or `serverResponseLost`, or anything in `NSURLErrorDomain`. A second check, `indicatesServerBusy`, covers `serviceUnavailable`, `requestRateLimited` and `zoneBusy`. (`CloudKitStoreHealth` has similar lists but isn't compiled into the Assistant; copy the few codes rather than adding that file to the target.)
- `stopReason(for:)` returns a plain phrase for both ("iCloud couldn't be reached", "iCloud is busy"), so `attach` stops at once with the rest in `failed`, rather than retrying mark by mark. `Outcome` gains `noConnection: Bool` and `retryAfter: TimeInterval?` (from `CKErrorRetryAfterKey`, when present).
- `current(_:container:)` runs its server fetch through `database.configuredWith(configuration:)` with `timeoutIntervalForRequest` about 15 s. On timeout it already falls back to the store's copy.
- `CDAttendanceStore.ShareAttachResult` gains `noConnection` and `retryAfter`, passed through from the outcome.
- The notebook's other caller (`ClassroomAttendanceCatchUp`) shows `stoppedBecause` as "…because iCloud couldn't be reached.", which reads correctly, and stopping early offline is what it wants too.
- `share(_:to:)` itself can't be given a timeout (it blocks its thread until CloudKit answers); that stays as it is.

### Fix 4: a shorter rest after a network failure

- In `AssistantShareAttacher.afterRound`: when the round's result has `noConnection`, the rest is 30 s doubling to at most 2 minutes, rather than 1 doubling to 10. Fix 1 catches the network coming back; the short rest covers weak Wi-Fi that never drops. Other refusals keep today's rest.
- When `retryAfter` is present, the rest is at least that long.
- A new pure `rest(afterFailures:noConnection:)` beside today's, so the existing rest test still holds and a new one covers the network schedule.

### Fix 5: the sync line says when it's offline

- `AssistantShareAttacher` gains an observed `isOffline: Bool`: set when a round ends with `noConnection`, cleared when a round puts anything in, and cleared by `forgetWaiting()`.
- `AssistantSyncStatusView.status(...)` gains `shareOffline: Bool = false`: with anything waiting and either the last export failed or the share step is offline, the status is `.waitingForNetwork`, which shows the existing "Not sent yet. They'll go when you're back online."

## Building it

Small and closely related, so build it **in this session, one fix after another, no agents**: about 200 lines, and agents would each need the background above. Order: 3, 4, 5 (the outcome fields flow from `ClassroomShareAttach` up to the line), then 1 and 2.

- Builds: `Scripts/locked_xcodebuild.sh` with the `Daybook Assistant` scheme. `ClassroomShareAttach.swift` and `UnsentChangesKeepAlive.swift` are also in the notebook, so build the `Cosmic Daybook` iOS scheme once at the end.
- Tests (`-only-testing:`, leased simulator, `-parallel-testing-enabled NO`, 1 simulator):
  - `AssistantShareAttacherTests`: an offline result rests 30 s and sets `isOffline`; a later success clears it; `retryAfter` lengthens the rest.
  - `UnsentChangesKeepAliveTests`: leaving the foreground with only waiting marks starts the keep-alive and calls the work; with none, it doesn't.
  - A new `AssistantNetworkWatchTests`: back online retries, Wi-Fi to cellular retries, staying on the same Wi-Fi doesn't, offline doesn't.
  - The notebook's tests for `ClassroomShareAttach.attach(_:using:)` (find them with grep): a `networkUnavailable` chunk stops the pass with everything after it in `failed` and no one-by-one tries; a wrapped one (`NSUnderlyingErrorKey`, `partialFailure`) does too.
  - The status tests in `AssistantSiriTests` that call `AssistantSyncStatusView.status(`: offline share step reads "waiting for network".
  - The whole Assistant suite once at the end. `~/.claude/bin/sim-lease --done` after.
- Update the build board (https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM) with a milestone for this plan when building starts.

## Checking it on a phone

Unit tests can't make a real network flaky. After the build, a device check becomes a Tide row in `Areas/App Development/Cosmic Daybook/To do.md`:

- Install the Assistant on a phone in the class. Turn on Settings › Developer › Network Link Conditioner, "100% Loss": tap a few marks, see "Not sent yet…". Turn the conditioner off: the marks go within a few seconds, without tapping or reopening.
- Walk out of Wi-Fi range with cellular on: marks tapped on the way go once cellular takes over.
- Tap a mark with "100% Loss" on, turn it off, lock the phone at once: the mark reaches the guide's Mac within about 25 s.
- The `shareAttach` log category (Console, the phone selected) shows each try and why it stopped.

## Not in this plan

- **Retrying while the phone sleeps.** iOS gives an app no dependable way to run on a schedule while suspended. A `BGAppRefreshTask` runs at the system's choosing (often hours later), so it would add code without making marks go live. Fix 2 gives every mark a try at lock time instead.
- **Retrying on a push that wakes a suspended app.** Possible (an app-delegate `didReceiveRemoteNotification` that flushes), but pushes come only when the guide changes something, so it's rarely timely. Worth adding later if the device check still shows marks left behind overnight.
- **The iCloud hold lifting only on an import or export.** `AssistantFilingHold` lifts after a later successful import or export, not a successful setup. After a launch with no network, if setup later succeeds but no import or export follows, marks could wait until one does. Not seen yet; worth a look if the device check shows marks stuck after a launch with no signal.

## Open questions

- None blocking. If her phone turns out to have cellular data switched off for the Assistant, Fix 1 can't help on cellular; that's her setting to change, not the app's.
