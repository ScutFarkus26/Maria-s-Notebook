# Name list freeze fix

> **Working on it.** Written 2026-10-06, from three crash reports pulled off Danny's iPhone that day.
> In short: stop the name list from asking iCloud questions on the main thread, which froze the app until iOS killed it.

## Goal

The notebook on Danny's iPhone was killed three times on 2026-10-06 (4:44, 5:36 and 6:24 PM; TestFlight builds 300000000008 and 300000000010). After this fix, neither the notebook nor the Daybook Assistant waits on iCloud on the main thread when a sync finishes, when the app comes back to the front, or when someone saves their name. A TestFlight build of both apps carries the fix.

## Progress
- [ ] Phase 1: Move the zone lookups off the main thread (session: here) · est. ~2–3% weekly · started at 96%
- [ ] Phase 2: Roll out both apps to TestFlight (session: here) · est. ~0.5–1% weekly

## Cost

About 3–4% of the weekly all-models limit (Max). At writing, 94% is used, so 6% is left until Sun 11 Oct, 3:59 PM (US Eastern). Extra usage is off. **Fits, with little room for a second fix round.** If Phase 1 runs long, the test `await` edits go to a Sonnet agent. Phase 2 is the one that could wait for the reset, but the crash keeps happening until it ships. The plan review ran on Fable, whose weekly window is separate.

## The crash

All three reports show the same thing. iOS's scene-update watchdog (`0x8BADF00D`, "exhausted real (wall clock) time allowance of 10.00 seconds") killed the app while it was moving to the background. The main thread was stuck here (symbolicated with the build 300000000010 archive's dSYM):

```
-[NSPersistentCloudKitContainer recordIDForManagedObjectID:]  → _PFRequestExecutor wait (dispatch_group_wait)
ClassroomNames.zoneName(of:in:)                ClassroomNames.swift:406
ClassroomNames.inPinnedClassroom(_:in:)        :388–389  (one lookup per row)
ClassroomNames.myRows(_:role:in:)              :378
ClassroomNames.foldMyRows(role:in:)            :179
ClassroomNames.writeWaitingName(...)           :139
ClassroomNames.Arrival.noteImport(...)         ClassroomNames+Arrival.swift:106
closure in Arrival.start()                     :83–93  (eventChangedNotification observer, queue: .main)
```

`recordID(for:)` hands a request to the CloudKit mirroring delegate and waits for the answer. The delegate answers requests in order, after its sync work, and right after an import there is usually more queued (the export), so the wait can pass 10 seconds. The two memory-pressure reports from the same day don't involve the app. The crash reports are in the session scratchpad. Recipe: memory note "pulling-phone-crash-reports".

## Every main-thread path to the lookup

`ClassroomNames.zoneName(of:in:)` is the only caller of `recordID(for:)` in the name list. These paths reach it on the main thread:

| Path | App | When |
|---|---|---|
| `Arrival.noteImport` → held `writeWaitingName` → `foldMyRows`/`myRows` | both | each successful import while a write is held (the crash) |
| `AppServicesLauncher.swift:124–128` → `writeWaitingName` | notebook | launch |
| `AssistantBootstrapper` (`.swift:161, :377`, `+Names.swift:75, :110`, `+Observers.swift:66`) → `AssistantNameStore.writeWaitingName` | Assistant | launch, after joining, leaving the Sample Class, **every return to the app** |
| `setMyName` → `upsert` → `fold`/`myRows` | both | Settings › Your name (`ClassroomYourNameCard.swift:101`), Assistant onboarding (`AssistantNameStore.swift:67`) |
| `myName` → `myRows` | notebook | the Your-name card opening (`ClassroomYourNameCard.swift:72`) |
| `snapshot` → `inPinnedClassroom` (only when `ownerRecordName` is nil) | both | Attendance, Restock, Siri and MCP wording |

Already off the main thread, not in scope: the duplicate cleanup (`DedupSyncState`, `DedupShareBoundary`, the lesson and track title merges), which runs on background contexts (`MigrationRunner.launchSweep`, `DeduplicationCoordinator.sweep` via `Task.detached`), and `ClassroomShareRelease+Live.swift:140–143`, inside `Task.detached`.

**Same shape, follow-up (not this plan):** `ClassroomSharingService.shareContents` (`Sharing/ClassroomSharingService+Contents.swift:15–64`) is main-actor `async` and calls `fetchShares(matching:)` synchronously, from share setup and Restock's banner (`+Setup.swift:109, 209`). Whether it waits on the mirroring delegate is undocumented. It's in Tide: [stop sharing setup and Restock's banner from waiting on iCloud on the main thread](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=In%20a%20new%20Claude%20session%2C%20stop%20sharing%20setup%20and%20Restock%27s%20banner%20from%20waiting%20on%20iCloud%20on%20the%20main%20thread).

## Decisions

- **The lookup moves off the main thread, and the work waits for it.** It doesn't get skipped. One `@concurrent nonisolated static` function asks for every row's zone in a single batched `recordIDs(for:)` call, so there is one wait instead of one per row. It copies the existing batched share lookup `CDAttendanceStore.shareZoneNames` (`Attendance/Store/CDAttendanceStore+ClassroomShare.swift:102–109`); the enum is main-actor by default (`project.pbxproj:1113`), hence the explicit `nonisolated`. The write paths (`writeWaitingName`, `setMyName`, `foldMyRows`) become `async`, in this order:
  1. Collect this person's rows' permanent object IDs on the main actor.
  2. Await the zone map off the main thread.
  3. Back on the main actor, **re-check identity**: `ClassroomIdentity.currentUserRecordName` is still the `me` read before the wait, and on the Assistant `writesHeld` is still false. Otherwise stop, and the caller's next trigger writes under the new account.
  4. **Refetch** the rows: an import merge can delete or refresh them across the wait, and touching a deleted fault throws. Skip `isDeleted` rows and those with no context, then filter and fold by `objectID` with the map.

  The behavior and rules of the 2026-10-05 sync hunt (#24: never fold across zones, the oldest survivor, a copy of the survivor is never deleted) stay exactly as they are. Only where the question is asked changes.
- **Three answers, not two.** For each row the map says one of three things:
  - **In zone Z**: it has a record ID.
  - **Not sent**: a temporary ID, the batch returned no record ID for it, or there is no CloudKit container at all. No container covers single-store users and every unit test, and it's what `nil` means today at `ClassroomNames.swift:406`, so the existing `foldMyRows == 1` tests keep passing.
  - **No answer**: the row wasn't in the batch because it appeared during the wait.

  The fold deletes a copy only when it is "not sent", or in the survivor's known zone. A copy with no answer is kept for the next run. When the survivor itself has no answer, only "not sent" copies go.
- **Reads never ask iCloud.** `snapshot`, `myName` and `name(forRecordName:)` stay synchronous for the screens. Where they need a zone (`inPinnedClassroom`), they read an in-memory map kept by the lookup. That map is warmed off the main thread from every `CDClassroomPerson` row (a small table): once the stores load, after every successful import (from the Arrival observer, whether or not a write is held), and after the Assistant rebuilds its stack (new store, new object IDs). A row the map has no answer for counts as in the pinned classroom, as an unexported row does today. **Behavior change, accepted:** in the short window before the first warm-up, the Assistant's `snapshot` with no known owner (`ClassroomNames+Arrival.swift:18–19`) may pick a previous classroom's guide row (`ClassroomNames.swift:205`). It's display-only and corrects itself within seconds.
- **One write at a time, both paths.** `writeWaitingName` and `setMyName` now suspend, so a second trigger (an import, a return to the app, a second quick save) could overlap. One serial gate covers both. A trigger during a run asks for one more run afterwards, the way `DeduplicationCoordinator` handles `rerunAfterPass`, **with the latest call's `role` and `save` closure**: the Assistant's closure captures `stack.container` (`AssistantNameStore.swift:80–93`), which is stale after a rebuild. A `setMyName` that's been overtaken by a newer one doesn't write, so the card's `stored = typed` matches what was saved.
- **The Arrival observer stays on `.main`** and stays on `eventChangedNotification`, since the Assistant still targets iOS 18. The held write now runs as a `Task` that Arrival keeps, so tests can await it.
- **Parking a pool thread.** The batched lookup can hold one cooperative-pool thread for up to its wait (10 s+). WWDC21 "Swift concurrency: Behind the scenes" warns against blocking pool threads. Accepted: the serial gate means at most one name-list lookup at a time, the warm-up shares that gate, and `CDAttendanceStore.shareZoneNames` already does the same.
- **Guards against a repeat.** The real guard is the code's shape: `recordID(s)(for:)` appears only inside the `@concurrent` function, which a grep checks. The new tests cover the logic that can actually go wrong: a trigger during a run gives exactly one more run, and it uses the latest closure; an account change during the wait writes nothing; a row deleted during the wait doesn't crash or get folded; a "no answer" copy isn't deleted; a superseded `setMyName` doesn't write. The `zoneNameOverride` seam becomes a batch override (`[NSManagedObjectID] -> [NSManagedObjectID: String]`) with a hook that lets a test act during the wait. Its 9 uses in tests move with it.
- **Ruled out:**
  - A cache that the main thread fills by asking iCloud on a miss: the first miss still blocks.
  - Storing each row's zone in the model: a schema change for a display list.
  - Dropping the zone check: it is the #24 fix.
  - Making `snapshot` async: it would ripple into every screen that words a line.
  - A "lookup ran on the main thread" test: by construction it can't fail.
- **Roll-out (Danny, 2026-10-06):** TestFlight for both apps right after the merge. Adding builds to a tester group waits for his word.

## Apple guidance

Checked 2026-10-06 against Xcode 27.0 (27A266a), iOS/macOS 27.0 SDKs. Xcode 27.1 RC and 27.2 beta 2 exist; neither changes Core Data or `NSPersistentCloudKitContainer`, so there's no need to update first.

- **`recordID(for:)`, `recordIDs(for:)`, `record(for:)`, `records(for:)`** (`NSPersistentCloudKitContainer_SwiftOverlay.h`; iOS 13+, not deprecated). All four are synchronous, with no async variant and no actor annotation. Apple's pages ([recordIDForManagedObjectID:](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/recordidformanagedobjectid(_:)), updated 2026-08-14) say nothing about blocking or threads. The wait is known only from our own crash stack (`_PFRequestExecutor wait`), and the plan is built on that observed behavior.
- **Sendability.** `NSPersistentCloudKitContainer` and `NSManagedObjectID` are `NS_SWIFT_SENDABLE` (`NSPersistentCloudKitContainer.h:46`), and so are `CKRecord.ID` and `CKRecord`. A `@concurrent` function can take the container and the IDs, which a Swift 6 type check confirmed. Phase 1's lookup relies on this.
- **Batching.** `recordIDs(for:)` returns only the IDs that have a record, which is what "not sent" means in the zone map. Apple doesn't say whether it is one wait or one per ID. The plan batches anyway, and Phase 1 notes how long the batch takes on a real store if that's easy to see in the log.
- **Typed event message** (`NSPersistentCloudKitContainer.EventChangedMessage`, `NotificationCenter.AsyncMessage`, iOS 27+, [page](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/eventchangedmessage) 2026-09-11). It exists, but the Arrival file compiles into the Daybook Assistant, which targets iOS 18, so the classic `eventChangedNotification` stays (see Decisions).
- **Blocking a concurrency-pool thread.** WWDC21 "Swift concurrency: Behind the scenes" says not to block cooperative-pool threads. The lookup does, on purpose, for one call at a time (see Decisions › Parking a pool thread).
- **No zone without the mirroring delegate.** `NSManagedObjectID.persistentStore` names the store, not the zone. `fetchShares(matching:)` is also synchronous and its waiting is undocumented, so it is no way around the lookup.
- There are no WWDC 2025 or 2026 sessions on these APIs.

## Phase 1: Move the zone lookups off the main thread
- Who: `feature-phase` agent on Opus 5.5 (high) in this worktree; the main session (Opus 5.5) reviews the diff and lands it. Danny's choice at the start (2026-10-06): a Fable agent was started first and stopped before it changed any code.
- Steps:
  - New `Cosmic Daybook/Sharing/ClassroomNames+Zones.swift`, holding:
    - the `@concurrent nonisolated` batched lookup, modeled on `CDAttendanceStore.shareZoneNames`;
    - the three-answer map;
    - the warm map for reads, with its warm-up;
    - the serial write gate (latest params, superseded `setMyName`);
    - the batch override seam with its during-the-wait hook.
  - `Cosmic Daybook/Sharing/ClassroomNames.swift`:
    - Remove the synchronous `zoneName(of:in:)`.
    - `inPinnedClassroom`, `myRows` and `foldCounting` take a map.
    - `writeWaitingName`, `setMyName`, `foldMyRows` and `upsert` become `async`: collect IDs → await → re-check identity → refetch → work.
    - Reads use the warm map.
    - Update the doc comment's rule list.
  - `Cosmic Daybook/Sharing/ClassroomNames+Arrival.swift`: the held write runs as a kept `Task`, and every successful import also warms the map.
  - Callers:
    - `AppCore/AppServicesLauncher.swift` (await, and warm after the stores load)
    - `Settings/Classroom/ClassroomYourNameCard.swift`
    - `Daybook Assistant/Onboarding/AssistantNameStore.swift`: `save`, `setInList` and `writeWaitingName` become async, `writesHeld` is re-checked after the wait, and the callers in onboarding and `AssistantNameSheet.swift` follow.
    - `Daybook Assistant/Sync/AssistantBootstrapper*.swift`: warm after a stack rebuild.
  - Tests:
    - Update the `ClassroomNames*` suites, `ClassroomNamesArrivalTests` (await Arrival's kept task) and the four Assistant suites below for async and the batch seam.
    - Add the five logic tests listed under Decisions › Guards.
    - If the call-site churn is large and tokens are short, the mechanical `await` edits to tests may go to one Sonnet `refactor-light` agent once the API compiles.
  - Tide: a Build & fix row in Cosmic Daybook for the `shareContents` follow-up.
- Cost: ~2–3% of weekly. That's ~10 app files and ~9 test files with ~80 call sites turning `async`, three scheme builds, 13 focused suites, two whole suites and a review. The 9-file "Who made a change" fix was ~1% with far fewer tests.
- Done when:
  - `Scripts/locked_xcodebuild.sh` builds the `Cosmic Daybook` scheme for the leased iOS simulator and for macOS, and the `Daybook Assistant` scheme for its simulator, with zero new warnings.
  - `-only-testing:` passes for `Cosmic Daybook Tests/ClassroomNamesTests`, `ClassroomNamesZoneTests`, `ClassroomNamesEdgeCaseTests`, `ClassroomNamesArrivalTests`, `ClassroomNamesNotebookTests`, `ClassroomNamesWordingTests`, `AttendanceEmailLogTests`, `BackupClassroomNamesRoundTripTests`, `RestockStapleTests`, the five new logic tests, and the Assistant suites in `AssistantSyncJoinLeaveTests.swift`, `AssistantSiriRestockTests.swift`, `AssistantSplitStoreTests.swift` and `AssistantOnboardingTests.swift` (iOS simulator, `-parallel-testing-enabled NO`, one simulator).
  - Each new logic test fails when its guard is temporarily removed: the identity re-check, the refetch, the "no answer" keep, the rerun's latest closure and the superseded-save check. Each is checked once, then restored.
  - `grep -rn "recordID(for:\|recordIDs(for:\|record(for:" "Cosmic Daybook/Sharing/ClassroomNames"*` shows only the `@concurrent` function.
  - Then the whole `Cosmic Daybook Tests` suite once, and the whole `Daybook Assistant Tests` suite once. Any failure the change didn't cause is checked on main and noted.
  - Committed, with a short `/code-review` of the diff and its fixes, and landed on main (update-ref if the main checkout is on another branch; memory "merge-when-checkout-shared"), pushed.
- Hand off: no.

## Where Phase 1 stands (2026-10-06, evening)

- f43b99cc, the fix: three builds pass, the focused suites pass (69 notebook + 32 Assistant), then the whole suites pass (2,754 notebook, 264 Assistant).
- A code review found six edge-case races in f43b99cc, all during the new wait. None is a crash or deadlock. A `feature-phase` agent (Opus 5.5) was sent to fix them, each with a test:
  1. `setMyName` (ClassroomNames.swift ~109): when the account changed during the wait, return `.nothing` without touching `ClassroomIdentity`. Today it stores the old account's typed name as waiting, and the Assistant then writes it into the new account's row.
  2. `setMyName` (~104–115): mark the name waiting (`displayName`, `nameWaitingAs`) **before** the gate and lookup, so a rename survives the app being suspended or quit mid-wait. Square this with 1.
  3. `writeWaitingNameOnce` (~180 vs ~187): look up zones for the store `waitingRole ?? deviceRole` writes to, not only `deviceRole`'s.
  4. `myRows` on the write paths (ClassroomNames+Zones.swift ~163): leave out `.noAnswer` rows when a classroom is pinned. Reads still count them in.
  5. `writeWaitingNameOnce` (~166): check the stores again after the lookup, since an Assistant stack rebuild mid-wait leaves an empty context. In `AssistantNameStore`, skip when the bootstrapper's stack is no longer the one passed in.
  6. `ClassroomYourNameCard.swift` (~79): compare against the name being saved, not `stored`. Otherwise "change it, change it back" during a save drops the second change.
- Fixed in 0dab11dc: all six, five with tests. The focused suites pass (74 notebook, 33 Assistant).
- Left for later, in Tide:
  - [check that each new name-list test fails when its guard is removed](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=In%20a%20new%20Claude%20session%2C%20check%20that%20each%20new%20name-list%20test%20fails%20when%20its%20guard%20is%20removed)
  - [have the Assistant's name save notice when its storage was rebuilt](tide://box/Areas/App%20Development/Daybook%20Assistant/To%20do.md?text=In%20a%20new%20Claude%20session%2C%20have%20the%20Assistant%27s%20name%20save%20notice%20when%20its%20storage%20was%20rebuilt). That's the part of finding 5 that was left out; nothing is lost without it.
- Next: run both whole suites again, land on main, push, then Phase 2.

## Phase 2: Roll out both apps to TestFlight
- Who: main session (Opus 5.5, high) with the `roll-out` skill.
- Steps: archive and upload the notebook (iPhone/iPad and Mac) and the Daybook Assistant from main. No tester-group change without Danny's word. Add Tide rows (Cosmic Daybook › Check on a device): "After the name-list freeze fix build installs, use the iPhone app through a sync and switching away; check Settings › Analytics Data shows no new Cosmic Daybook reports." The same row goes in the Assistant's list for her phone once the build is in her group.
- Cost: ~0.5–1% of weekly (archive builds mostly wait in the build queue).
- Done when: both uploads accepted by App Store Connect (build numbers noted under Progress), and the Tide rows added with their `tide://` links in this file.
- Hand off: no.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board, if the plan lists one.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/<App>/To do.md`, `add_action`), skipping ones already there. Tide holds the row; the repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets the plan's status line and runs `docs-index` so the map follows.
7. If the next phase is a fresh session, print its starter prompt.

## Open questions
None.
