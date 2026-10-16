# Assistant sending on weak networks (2026-10-16)

> **Working on it.** Written 2026-10-16 from an investigation on branch `claude/assistants-attendance-upload-921752`.
> In short: the Assistant's marks sometimes sit on her phone for minutes, because nothing notices the network coming back, locking the phone doesn't retry waiting marks, and a weak link stalls sending; five fixes make it retry at the right moments and say plainly when it's offline.

## Goal

An assistant's marks reach the guide within seconds of her phone getting a usable connection: when Wi-Fi comes back, when the phone switches between Wi-Fi and cellular, and when she locks the phone right after tapping. A weak link no longer holds every later mark behind one slow try. When her marks can't go, the sync line says "Not sent yet. They'll go when you're back online." instead of "Sending to iCloud…" indefinitely.

## Progress
- [x] Phase 1: Network failures stop the pass and say so (fixes 3, 4, 5) (session: here) · est. ~1–3% weekly · started at 91% · actual <1% (91→91). 66 Assistant tests (5 suites) and 28 notebook tests (3 suites) pass on the iOS simulator. Differed: the sync line reads "offline" only while marks wait (`shareOffline && waitingForShare > 0`); an early try after a fresh mark goes in also waits for CloudKit's retry-after; `serverResponseLost` counts as no connection, as planned.
- [ ] Phase 2: Retry when the network returns and at lock (fixes 1, 2), then finish (session: here) · est. ~1–2% weekly

## Cost
About 2–5% of the weekly limit (Max plan), from past main-session phases of this size (each ~1%), plus ~1% already spent on this planning (the Apple check and the review). 10% is left until the weekly reset on Sunday 18 October; extra usage is off. Fits, though only just with room for one more job of this size this week. If a phase runs over, Phase 2 can wait for the reset.

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
- **A weak link stalls the whole queue.** One pass at a time. Each chunk first fetches the share's latest copy from the server (`ClassroomShareAttach.current`, default CloudKit timeouts), then calls `share(_:to:)`. When a chunk fails with a network error, the pass retries **each mark on its own**, each with its own fetch and call, instead of stopping. On a weak link one pass can take minutes, and marks tapped meanwhile wait behind it.
- **The sync line hides it.** "Not sent yet. They'll go when you're back online." shows only when CloudKit's own export failed. When the share step fails for lack of network, the line says "Sending to iCloud…" indefinitely, so she can't tell her marks are stuck.

Settings on her phone can cause the same symptom and are worth checking before blaming the code: Settings › Cellular › Daybook Assistant switched off (nothing goes on cellular), Low Data Mode, Low Power Mode, and Background App Refresh off (no push wakes).

## Decisions

- **Build here, in the main session, no agents.** About 300 lines across ten files, all resting on the investigation above. An agent would need that background re-explained, and its setup costs more than the work. With 10% of the week left, the cheapest safe route wins.
- **Two phases, run one after the other.** They touch different files and could run in parallel sessions, but a second session would reload the background for no gain on a job this size.
- **No questions for Danny.** Every choice below has a clear default from the code; none changes what he sees beyond the sync line's existing offline wording.
- **The network watch triggers a retry; it doesn't gate one.** A mark is always tried after a save whatever the watch says. The watch only adds a try when the network comes back or changes, so a wrong answer from it can only cost one extra try. (See Apple guidance.)
- **Network failures get a short rest (30 s, doubling to 2 min), other refusals keep today's (1 to 10 min).** The long rest was for a CloudKit that keeps refusing; a network failure is cheap to retry once fix 3 stops the pass at the first one.
- **`hasUnsentWork` stays as it is.** Leave reads it (`AssistantBootstrapper.unsentMarks`) and already counts waiting marks separately; widening it would muddle Leave's message. Lock time gets its own `hasWaitingWork` closure instead.
- **The shared files keep the notebook's behavior** except where the change helps it too: `UnsentChangesKeepAlive`'s new closure defaults to `{ false }`; `ClassroomShareAttach` stopping on a network failure also helps the notebook's catch-up (`ClassroomAttendanceCatchUp`), whose message then reads "…because iCloud couldn't be reached."
- **Other notebook callers of `ClassroomShareAttach.attach` change too, for the better:** the guide's Set Up Classroom Sharing (`ClassroomSharingService+Setup.swift`, whose second pass is skipped once a pass stops), `SharedStoreOrphanGuard`, and the catch-up all stop at the first network failure instead of grinding through every record, and each keeps what's left to try again. Manage Sharing's `current()` is deliberately left alone (Phase 1).
- **Respect CloudKit's retry-after everywhere (G4).** Every extra trigger in this plan goes through `retryWaiting()`, so that's where the `notBefore` is enforced.
- **The lock retry is limited to marks with a chance** (offline, or rest over), so a mark that will never go doesn't wake a background task at each lock.
- **Copy the few CloudKit codes into `ClassroomShareAttach`** rather than adding `CloudKitStoreHealth.swift` to the Assistant target: that file drags in more of the notebook.
- **Ruled out: retrying while the phone sleeps.** iOS gives an app no dependable way to run on a schedule while suspended. A `BGAppRefreshTask` runs at the system's choosing (often hours later), so it would add code without making marks go live. Fix 2 gives every mark a try at lock time instead.
- **Ruled out for now: retrying on a push that wakes a suspended app.** Possible (an app-delegate `didReceiveRemoteNotification` that flushes), but pushes come only when the guide changes something, so it's rarely timely. Worth adding if the device check still shows marks left behind.
- **The keep-alive still starts on `didEnterBackground`**, though Apple prefers starting the background task before the app leaves (G6). That's how it already works, iOS grants a few seconds' grace either way, and moving it to `willResignActive` would also fire for Control Center and notification pulls. Not worth changing here.
- **Not touched: the iCloud hold lifting only on an import or export.** `AssistantFilingHold` lifts after a later successful import or export, not a successful setup. After a launch with no network, if setup later succeeds but no import or export follows, marks could wait until one does. Not seen yet; worth a look if the device check shows marks stuck after a launch with no signal.

## Apple guidance

Checked 2026-10-16 against Xcode 27.0 (27A266a), iOS 27.0 SDK, by an `sdk-verifier` agent. Xcode 27.1 is out and 27.2 is in beta; neither's notes touch Network, CloudKit, Core Data sharing or background tasks, so nothing here waits on updating.

- **G1. Watching the network.** `NWPathMonitor` conforms to `AsyncSequence` of `NWPath` from iOS 17 (`Failure == Never` from iOS 18), so `for await path in monitor` works at the Assistant's iOS 18 target. Its iterator isn't `Sendable`: consume it in one task. A Wi-Fi ↔ cellular switch arrives as a new path; compare `usesInterfaceType(.wifi)` / `(.cellular)` with the previous one. `linkQuality` and `isUltraConstrained` are iOS 26 only: don't use them. The docs page is bare. [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor) (8 Oct 2026).
- **G2. Trigger, not gate.** CloudKit's own `networkUnavailable` page says to "monitor for network reachability and wait to reissue the operation when the network is available again". Apple's networking engineers warn that reachability gives false positives and negatives, so never refuse to try because the monitor says offline (forum guidance, not docs: [thread 105822](https://developer.apple.com/forums/thread/105822)). Hence Decisions: the watch only adds tries. [CKError.Code.networkUnavailable](https://developer.apple.com/documentation/cloudkit/ckerror/code/networkunavailable) (8 Oct 2026).
- **G3. A shorter fetch timeout.** `CKDatabase.configuredWith(configuration:group:body:)` (iOS 15, async overload available) applies a `CKOperation.Configuration` to "the methods you execute in the closure". Apple's examples use `records(for:)`, and whether the single-record `record(for:)` honors it isn't documented: use `records(for: [id])` inside the closure. `timeoutIntervalForRequest` defaults to 60 s and, as in URLSession, measures idle time between data, not the whole request. [configuredWith](https://developer.apple.com/documentation/cloudkit/ckdatabase/configuredwith(configuration:group:body:)-637p1) (8 Oct 2026).
- **G4. CloudKit's error codes.** `networkUnavailable` (3), `networkFailure` (4), `serviceUnavailable` (6), `requestRateLimited` (7), `zoneBusy` (23), `serverResponseLost` (34) all exist, none deprecated. Network failures: retry with a backoff. `requestRateLimited`, `zoneBusy`, `serviceUnavailable`: wait at least `CKErrorRetryAfterKey` when given (read it for all three; Apple's pages disagree on which carry it). `serverResponseLost`: the server may have done it, so check server state before redoing a non-idempotent call; for `share(_:to:)` that's already the case, since every call is preceded by `unshared()`. [CKError.Code](https://developer.apple.com/documentation/cloudkit/ckerror/code), [TN3162](https://developer.apple.com/documentation/technotes/tn3162-understanding-cloudkit-throttles) (8 Oct 2026).
- **G5. `share(_:to:)`.** No documented network requirement, timeout or offline behavior; the completion fires once the objects are assigned to the share, "not necessarily when the objects have been exported". The blocking-until-the-server-answers behavior the code works around is observed, not documented, and has no knob. No WWDC25/26 changes. [shareManagedObjects:toShare:completion:](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/sharemanagedobjects:toshare:completion:) (8 Oct 2026).
- **G6. Time after the phone locks.** `beginBackgroundTask(withName:expirationHandler:)` is current through iOS 27, and Apple's own example is saving data to a server. Apple prefers calling it before the app enters the background rather than in `didEnterBackground`. `BGContinuedProcessingTask` (iOS 26+) is not a fit: it must start from a person's action, shows a Live Activity, and is for work of minutes or more. [Extending your app's background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time) (8 Oct 2026).

## Phase 1: Network failures stop the pass and say so

- Who: main session (Opus 5.5, high: shared sync code where a mistake leaves marks unsent without anyone noticing).
- Steps:
  - **Fix 3**, `Cosmic Daybook/Sharing/ClassroomShareAttach.swift` (compiled by both apps):
    - New `static func indicatesNoConnection(_ error: NSError) -> Bool`: true when the error, or any `NSUnderlyingErrorKey` or `CKPartialErrorsByItemIDKey` error inside it, is CloudKit's `networkUnavailable`, `networkFailure` or `serverResponseLost`, anything in `NSURLErrorDomain`, or Core Data's 134060 timeout (G4). A second, `indicatesServerBusy`, covers `serviceUnavailable`, `requestRateLimited` and `zoneBusy`. A `serverResponseLost` is safe to try again later because each call is preceded by `unshared()` (G4).
    - `stopReason(for:)` returns "iCloud couldn't be reached" for no connection (134060 keeps "iCloud took too long to answer") and "iCloud is busy" for busy, so `attach` stops at once with the rest in `failed`, instead of retrying mark by mark.
    - `Outcome` gains `noConnection: Bool` and `retryAfter: TimeInterval?` (`CKErrorRetryAfterKey`, read for all three busy codes, G4).
    - **The pre-share fetch decides first.** A new `latestForAttach(_:container:) async throws -> CKShare` fetches through `database.configuredWith(configuration:)` with `timeoutIntervalForRequest` about 15 s and `timeoutIntervalForResource` about 30 s (a trickling link never trips the idle timeout alone), using `records(for: [id])` rather than `record(for:)` (G3). When that fetch fails with `indicatesNoConnection` it **throws**, so `Steps.live.share` never calls `share(_:to:)` offline: `share(_:to:)` is observed to block rather than fail when offline (G5), which would leave `noConnection` unset. Any other fetch failure falls back to the store's copy, as today.
    - `current(_:container:)` stays as it is, default timeouts and all: the guide's Manage Sharing (`ClassroomSharingService+Members.swift:154`) uses it, and falling back to the stored copy more often there risks a stale change tag in `persistUpdatedShare`.
    - `share(_:to:)` itself can't be given a timeout (G5); it stays as it is.
  - `Cosmic Daybook/Attendance/Store/CDAttendanceStore+ClassroomShare.swift`: `ShareAttachResult` gains `noConnection` and `retryAfter`, passed through from the outcome.
  - **Fix 4**, `Daybook Assistant/Sync/AssistantShareAttacher.swift`:
    - A new pure `rest(afterFailures:noConnection:)`: 30 s doubling to 2 min when `noConnection`, today's 1 to 10 min otherwise. Two counters, `networkFailuresInARow` and `failuresInARow`: each kind backs off on its own count, and a success resets both.
    - `retryAfter` sets a `notBefore` time that `retryWaiting()` respects: it clears the rest but never moves `backlogWaitsUntil` earlier than `notBefore`. So the foreground return, the network watch and the lock retry (Phase 2) can't cut a rate-limited wait short (G4). A just-saved mark is still tried at once.
  - **Fix 5**, same file: an observed `isOffline: Bool`, set when a round ends with `noConnection`; cleared when a round puts anything in, by `forgetWaiting()`, when `flush` sees a rebuilt stack, and when mirroring stops. `Daybook Assistant/Sync/AssistantSyncStatusView.swift`: `status(...)` gains `shareOffline: Bool = false`, **and the view's `status` property (lines 36–43) passes `AssistantShareAttacher.shared.isOffline`**. With anything waiting and either the last export failed or the share step is offline, the status is `.waitingForNetwork`.
- Cost: ~1–3% of weekly (a sync change across six files in the main session; past main-session phases of this size came in around 1%).
- Done when:
  - `Scripts/locked_xcodebuild.sh` builds the `Daybook Assistant` scheme for the simulator.
  - On the leased simulator (`-parallel-testing-enabled NO`, 1 simulator), new and existing tests pass:
    - `-only-testing:"Daybook Assistant Tests/AssistantShareAttacherTests"`: an offline result rests 30 s and sets `isOffline`; a later success clears it, and so does a rebuilt stack; three network failures then one refusal rests 1 min, not 8; a `retryAfter` of 300 s holds even when `retryWaiting()` is called; a fresh mark during that wait is still tried; the existing "rest is a minute, doubles…" test still passes unchanged.
    - `-only-testing:"Daybook Assistant Tests/AssistantSiriTests"` (holds the `AssistantSyncStatusView.status(` tests): an offline share step reads as waiting for the network.
    - The notebook's `ClassroomShareAttachPassTests`, `ClassroomShareFix1010ATests` and `ClassroomSharingWordingTests` (`-only-testing:"Cosmic Daybook Tests/…"`), **on the iOS simulator only** (a macOS test run opens Danny's live store): a `networkUnavailable` chunk stops the pass with everything after it in `failed` and no one-by-one tries; the same error wrapped in `NSUnderlyingErrorKey` and in `partialFailure` does too; 134060 sets `noConnection`; a `requestRateLimited` with a retry-after carries it into the outcome. `ClassroomSharingWordingTests.swift:17` expects `stopReason` nil for CloudKit code 4: update it to "iCloud couldn't be reached".
  - Phase 1 is safe to land on its own: if Phase 2 waits for the weekly reset, nothing here depends on it.
- Hand off: no.

## Phase 2: Retry when the network returns and at lock, then finish

- Who: main session (Opus 5.5, high).
- Steps:
  - **Fix 1**, new `Daybook Assistant/Sync/AssistantNetworkWatch.swift`: one `NWPathMonitor` read as an `AsyncSequence` in a single task (G1), a retry trigger and never a gate (G2).
    - Kept as a static in `AssistantStack` like `keepAlive`: `shared()` makes it (not for the sample class), and `rebuild()` stops the old one before `shared()` makes a new one.
    - The first path after it starts only records the state (the launch already flushes). After that, when the path goes from unusable to usable, or stays usable but changes interface (Wi-Fi ↔ cellular), wait about 3 s for the link to settle, then call `AssistantShareAttacher.shared.retryWaiting()` on the main actor. Changes within the settle time collapse into one retry.
    - Testable without a real monitor (`NWPath` has no public init): the watch takes its paths as an injected `AsyncStream` of a small value type (usable, interface kind) and an injected sleep; the live init maps `NWPath` into it. The decision is a pure static `shouldRetry(from:to:)`. Event-driven, no polling (the efficiency-pass rules for new background code apply).
    - **A second trigger, closer to G2:** a successful export or import of the shared store proves iCloud is reachable. `AssistantSyncRecord` already hears those events; it gains an `onSharedStoreSynced` callback, which `AssistantStack` sets to "if the attacher `isOffline`, `retryWaiting()`".
  - **Fix 2**, `Cosmic Daybook/Services/Sync/UnsentChangesKeepAlive.swift` (compiled by both apps): a new init closure `hasWaitingWork: @MainActor () -> Bool = { false }` and an internal `needsKeepAlive` (`hasUnsentWork || hasWaitingWork()`) that `didLeaveForeground` uses. In `Daybook Assistant/Sync/AssistantStack.swift`: `hasWaitingWork` is true when marks wait **and** either the attacher `isOffline` or its rest is over (a new `backlogIsDue`), so marks that will never go (a stray in another share zone, `+Zone`) don't cost a background task at every lock. `waitForWork` becomes `retryWaiting()` then `waitUntilIdle()`, so waiting marks get a real try within the same 25 s limit, under the existing `beginBackgroundTask` (G6). Siri's path is untouched (it uses `UnsentChangesKeepAlive.wait(atMost:for:)` with its own closure).
  - Finish: build the `Cosmic Daybook` iOS scheme once (it compiles both shared files); run the whole Assistant suite once and the whole notebook suite once, iOS simulator only; `~/.claude/bin/sim-lease --done`.
- Cost: ~1–2% of weekly (same kind as Phase 1, plus the two whole suites, which cost time more than tokens).
- Done when:
  - `-only-testing:"Daybook Assistant Tests/UnsentChangesKeepAliveTests"`: `needsKeepAlive` is true with only waiting work, false with none; `sendBeforeSuspending` calls the work and returns within the limit; without `hasWaitingWork` passed (the notebook's case), `needsKeepAlive` equals `hasUnsentWork`.
  - New `-only-testing:"Daybook Assistant Tests/AssistantNetworkWatchTests"` (injected stream and sleep): the first path doesn't retry; back online retries; Wi-Fi to cellular retries; the same Wi-Fi again doesn't; going offline doesn't; three changes within the settle time make one retry.
  - `AssistantSyncRecordTests`: a successful shared-store export calls `onSharedStoreSynced`; a failed one and a private-store one don't.
  - The `Daybook Assistant` and `Cosmic Daybook` (iOS) schemes build; both whole suites pass on the leased simulator (1 simulator each run).
  - The device check below is a row in Tide.
- Hand off: no.

## Checking it on a phone

Unit tests can't make a real network flaky. At the end of Phase 2 this becomes a row in Tide (`Areas/App Development/Cosmic Daybook/To do.md`), linked here:

- Install the Assistant on a phone in the class. Turn on Settings › Developer › Network Link Conditioner, "100% Loss": tap a few marks, see "Not sent yet…". Turn the conditioner off: the marks go within a few seconds, without tapping or reopening.
- Walk out of Wi-Fi range with cellular on: marks tapped on the way go once cellular takes over.
- Tap a mark with "100% Loss" on, turn it off, lock the phone at once: the mark reaches the guide's Mac within about 25 s.
- The `shareAttach` log category (Console, the phone selected) shows each try and why it stopped.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board (https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM; one milestone for this plan, its two phases as steps) with the `build-board` skill, then `~/.claude/bin/board-touch <url>`.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. Tide holds the row; the repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets the plan's status line (`> **Working on it.**` after a phase, `> **Done <date>** (<commit>).` after the last, checked against main) and runs `docs-index` so the map follows.
7. Both phases run here, so there is no starter prompt to print. If Phase 2 has to wait for the weekly reset, first land Phase 1 and this plan on main (/close-out), then its starter prompt is: "Model: Opus 5.5, effort: high" then "In /Users/dannydeberry/Developer/Maria's Notebook, read docs/Plans/Plan - Assistant sending on weak networks.md and do Phase 2. Follow its Starting a phase and Ending a phase steps."

## Open questions
None.
