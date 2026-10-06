# Sync and sharing fixes

> **Working on it.** Written 2026-10-05 from the read-only hunt in [Sync and sharing bug hunt 2026-10-05](<../Reviews/Sync and sharing bug hunt 2026-10-05.md>). A, C and E are on main with schema 17 in Production (2026-10-06); B, D and F wait for the Oct 11 usage reset.
> In short: fix every finding of the 2026-10-05 sync and sharing bug hunt in six parallel agents, add who-changed-it to staple history (schema 17), and land it all on main.

## Goal

Every finding in the report is fixed, the 11 "fix first" ones and every smaller one:
- Siri marks reach the Assistant even when the notebook is closed.
- Duplicate cleanup no longer deletes what hangs off a copy.
- Stop Sharing on iPhone and iPad keeps the one share.
- Restores and stalled attaches no longer leave records out of the share.
- The sync status only says "synced" when something was sent.
- Leave on the Assistant can't drop an unsent mark.
- Remove Last Year runs exactly the plan the guide saw.
- Staple history shows each person's current name (schema 17).

Everything ends on main, built and tested on both apps and both platforms, with schema 17 deployed to CloudKit Production. Roll-out and device checks become Tide rows for Danny to pick up when he chooses.

## Progress
- [ ] Phase 1: Six fix agents in worktrees, A ‖ B ‖ C ‖ D ‖ E ‖ F (session: here) · est. ~8–12% weekly · started at 57%, 2026-10-05 21:10. **Changed 22:15:** the data-model plan was found fixing the same files in parallel (see Decisions › Overlap with the data-model plan). **C done** (`2f163a80`, merged into this branch as `545bbfb2`). Its tests passed: 93 in 11 suites. Assistant and notebook iOS builds are clean. It differed from the plan in three ways: Leave waits for the attach, then purges, then deletes only records CloudKit confirms are in no share; a new app-wide `AssistantSyncRecord` replaces reading `AssistantHistoryTrim`; the purge and the zone check are untested without a real share. A, D and E were stopped near the end of their work and kept as WIP commits (A `worktree-agent-aaa0baf22bedd002f` f31cf9e5, D `worktree-agent-a3a09e5b116165d2f` 3cafbb13, E `worktree-agent-a2e5fe33fff81540a` 1c687cd7; unfinished, untested). B and F are held.
- [ ] Phase 1b (**resumed 2026-10-06 06:40** on Danny's go-ahead: the data-model session, stalled since ~01:00 at its Phase 2, was messaged to carry on to main; Phase 1b and 2 run as soon as it lands, past the 85%/90% lines. The pause note follows. **Paused 2026-10-06 01:05:** the week was at 84%, and the data-model plan had finished its two agent waves but was only at its Phase 2 of 5, with main still `3fda274e`. Its remaining phases will likely carry the week past the 85% no-new-agents line before it lands, so Phase 1b runs after Sunday's reset, Oct 11 4 PM EDT, unless Danny says otherwise): After `Plan - Data model and launch repair fixes.md` lands on main: re-scope A, B, D, E and F to what it didn't fix, rebase, relaunch (session: here) · est. to be re-estimated
- [x] Phase 1b-now (2026-10-06 09:00, week at 88%; **done 10:30**: A `a5888b34` merged `4a4d9de2`, E `29d16f32` merged `21a5ae3b`): main merged in (`e66842dc`, data-model squash `0ab967ff`). Narrowed **A and E** now; **B, D, F wait for Sunday's reset** (the data-model plan measured ~3–4% weekly per Core Data fix agent with three build targets, 2.5× the estimate, so all five plus Phase 2 would not fit in the 12% left). Hard stop at ~96% weekly.
- [x] Phase 2a: Combine C + A + E, schema 17 to Production, full builds and suites, review, docs, main (session: here). **Done 2026-10-06:** squashed onto main and pushed (see the commit titled "Fix the 2026-10-05 sync and sharing hunt: Assistant sync, share setup, names, schema 17"). Schema 17 deployed to Production at ~12:30 after Danny signed in to CloudKit Console: the deploy sheet listed only 2 fields and 3 indexes on `CD_SupplyTransaction` (`CD_changedByID STRING QUERYABLE SEARCHABLE SORTABLE`, `CD_changedByID_ckAsset ASSET`, added by hand in Development exactly as Core Data's init makes a text attribute), both confirmed in Production. Before that, ~11:00:
  - Builds: iOS, Mac and Assistant are clean. Whole suites pass: notebook 2,708, Assistant 264.
  - The Opus review found 7 issues; 6 were real and are fixed in `1ecec889`:
    - the Assistant name gate
    - the only-share fallback with a pin present
    - Leave's unsorted marks
    - a remote pin waits for an import
    - an account switch while the app was closed
    - the catch-up never waits behind a stuck pass

    One was a false positive (`current` is already `@concurrent`).
  - Docs are in `d914f908`.
  - **Stopped at schema 17:** the leased simulator has no iCloud account (the init failed with 134400), and CloudKit Console in the browser pane needs Danny's sign-in. A Debug Mac run would open the real Development notebook, so that was ruled out. Main waits, since merging before the deploy risks a roll-out breaking staple-history sync. Danny's row: [Sign in to CloudKit Console, then tell this session to deploy schema 17 and land](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Sign%20in%20to%20CloudKit%20Console%20in%20Claude%27s%20browser%20pane%2C%20then%20tell%20the%20Sync%20%26%20sharing%20session%20to%20deploy%20schema%2017%20and%20land%20its%20fixes).
  - **Then (done):** the two fields added by hand in Development (the text attribute's String field plus its `_ckAsset` Asset field, with Queryable/Searchable/Sortable on the String, matching `CD_reason`), deployed and confirmed in Production, squashed to main, pushed.
- [x] Phase 1c + 2b (run 2026-10-06 on Danny's word rather than after the reset, week at 90%): B `95cf040f`, D `b8223d83`, F `52870031`, merged. An Opus review found 7 issues; 5 were real and are fixed. Builds clean on iOS, Mac and Assistant; notebook 2,740 and Assistant 264 tests pass. Squashed to main · Danny's row: [After Sunday's usage reset, finish the sync and sharing fixes](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20Sunday%27s%20usage%20reset%2C%20ask%20Claude%20to%20finish%20the%20sync%20and%20sharing%20fixes%20%28sync%20status%2C%20Remove%20Last%20Year%2C%20four%20small%20stack%20items%29)
- [ ] Phase 2 (as written below; split into 2a and 2b above): Combine, schema 17 to Production, full builds and suites, review, docs, main (session: here) · est. ~2–4% weekly

## Cost

About 11–17% of the weekly all-models limit on Max, including ~1% already spent planning. 44% is left (56% used at writing) until Sun Oct 11, 4 PM EDT. **Fits.**

The six parallel agents also draw on one 5-hour window. The window was 46% used at writing and resets at 9:40 PM EDT, so start Phase 1 after that. Start A, C, D and E together, and B and F when two of those have replied (or about an hour later), so six xhigh agents don't fill one window.

The sizes come from the cost log:
- ClaudePic's six bug-fix agents came to ~0.5% each.
- The names deep agent (~570k tokens) was the bulk of a ~4% plan.
- A, C, D and E here each carry 8–14 changes, 10–20 suites and 2–3 scheme builds at xhigh, so they're sized above ClaudePic's (the plan review's estimate).

## Decisions

**Scope** (Danny, 2026-10-05):
- The sync and sharing hunt only, every finding including the smaller ones.
- Three findings overlap the same day's data-model hunt: #1 Siri marks, #4 the 2,000 cap, and the work-item check-in sweep in #2. They're fixed here. The data-model hunt's list waits for its own plan, which should skip those three.

**Stop Sharing on iPhone and iPad** (Danny): it removes everyone and keeps the share, as on the Mac (`removeAllMembers()`). Apple's sheet always offers the owner its own Stop Sharing, which deletes the share and can't be hidden. So the guide's iPhone and iPad move to the app's own members sheet, as the Mac already uses.

**Staple history names: schema 17** (Danny, after weighing it):
- **Best practice is to store who, not their name.** Attendance, sends, Restock and orders already show current names. Freezing the name is for legal audit logs.
- **What changes:** `CDSupplyTransaction` gains one optional string, `changedByID` (default `""`). The model is edited in place, as for schema 16.
  - `currentSchemaVersion` goes 16 → 17.
  - Backup format goes v38 → v39, with a line in `Backup/BackupEntityTable.swift` if needed (the model-driven rows may already carry it).
- **Old builds stay readable.** New rows keep writing `reason` as "Low · Ana" (the stamped name). New builds show the part before " · " plus the current name looked up from `changedByID` through `ClassroomNames`.
- **Old rows** with an empty `changedByID` show what they always did.
- **Order of steps:** the Development schema init and the Production deploy happen in Phase 2, before merging, with Danny's yes before Deploy. No device runs it until a roll-out Danny chooses.

**Stop at main** (Danny): merge and push. Roll-out (notebook and Assistant together, the Assistant to the "Assistants" group) is a Tide row.

**One owner per file.** Each agent owns a list of files, and no two agents edit the same file. The only exception is `AppCore/Constants/UserDefaultsKeys.swift`:
- B scopes the three last-error keys.
- D scopes the Reset Local Cache request key.
- Separate lines, so the merge is clean or a one-line fix.

A file not on any list may be edited by the agent whose finding needs it; it says so in its reply.

**No agent calls code another agent adds.** One cross-agent seam is wired in Phase 2 instead: B adds `CloudKitSyncStatusService.beginEarlyEventCapture(for:)`, and Phase 2 step 1 calls it from `AppBootstrapping.getSharedCoreDataStack` (A's file) right after the stack is made. `configure` runs only after the window's bootstrap, too late for the setup events `loadPersistentStores` posts, and never on a Siri background launch.

**Settled without asking** (sensible defaults):
- **Siri filing.** `SiriHost.didSave` mirrors the Assistant's `AssistantSiriHost.didSave`: start the guard (it is idempotent), queue the created IDs, flush.
- **The keep-alive's unsent rule.** It tracks the *newest* save, not the first. `UnsentChangesKeepAliveTests.firstSaveCounts` pins the old rule and gets rewritten. Leave must never purge a mark an export didn't carry.
- **Retries.** They stop pretending to be Sync Now. Success is stamped only by a successful import or export event, never by a remote-change notification alone.
- **Dedup merges.** Same-`id` dedup for Track, Lesson, TodoItem and CommunityTopic moves children onto the survivor, reusing the moves that `merge(duplicateTrack:)` and `merge(duplicate:into:)` already make for the same-title merges.
- **Remove Last Year.** If the start date changed since the preview, the run refuses and shows the new preview. It doesn't silently re-plan.
- **The front-desk email settings row.** Written only on an explicit edit (the same rule as `SchoolYearSync`), never at launch or when the settings screen opens.

**Overlap with the data-model plan** (Danny, 2026-10-05 22:15): the same day's `Plan - Data model and launch repair fixes.md` (worktree `data-model-launch-repairs-063ae8`) fixes all 64 of its findings, and its agents were already running in the same files: `SharedStoreOrphanGuard`, `SiriHost`, `ClassroomShareAttach` and setup, `ClassroomShareRelease*`, `ClassroomNames`, `PersistentHistoryProcessor`, the status service's event handlers, `AppBootstrapping`, `CoreDataStack`, dedup merges, work check-ins and backup restore. **The data-model plan goes first and owns every finding both hunts share.** This plan waits for it to land on main, then:
1. Compares the two finding lists and drops what it fixed.
2. Rebases the A, D and E WIP branches onto that main, keeping only the remaining fixes.
3. Relaunches narrower agents for A, B, D, E and F.

C (Assistant sync) doesn't overlap and carried on.

**Overnight autopilot** (Danny, 2026-10-05 ~23:00):
- **Full autonomy.** Once the data-model plan lands, run Phase 1b and Phase 2 to the end, without asking. That includes deploying schema 17 to CloudKit Production and merging and pushing to main; the "ask Danny" steps in Phase 2 are pre-approved for this run.
- **Budget:** launch no new agents once the week passes 85% used, and stop all work at 90%, leaving the rest for after Sunday's reset.
- **If something can't be done alone,** such as CloudKit Console asking for a sign-in (Claude never enters passwords), stop there and leave it for the morning.

**Ruled out:**
- **A sweep to file records that look unshared.** It's what split the classroom on 2026-09-28. Every fix files records where they're created or restored.
- **Bringing back `.first` or moving already-shared records.** No fix does either.

## Apple guidance

Checked 2026-10-05 against Xcode 27.0 (27A266a), iOS/macOS 27.0 SDKs (sdk-verifier, Sonnet). The notebook targets iOS/macOS 27.0; the Daybook Assistant targets iOS 18.0. Xcode 27.1 RC and 27.2 Beta 2 change nothing here, so there's no need to update first.

**Remote change vs. sync** (`NSPersistentStoreCoordinator.h:152-157`; [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users), 14 Aug 2026):
- The header says the remote-change notification is posted "for every write to the store", and also "all cross process writes". Apple contradicts itself, so a remote change proves nothing about iCloud.
- Use `NSPersistentCloudKitContainer.Event` `.import`/`.export` (`succeeded`, `endDate`) for sync state, and the history author for "is this mine". → B step 1.
- The typed `.remoteChange` and `.eventChanged` messages are iOS/macOS 27 only. Files the Assistant compiles stay on `.NSPersistentStoreRemoteChange` and the classic event notification. → A, C.

**Setup events and the stopped flag** ([TN3164](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer), 14 Aug):
- Apple documents no setup re-run after an account change, and doesn't say a later setup success means recovery. Treat a failed setup as lasting.
- 134406 means requests are aborted because the delegate never initialized. → B step 5 clears the flag only on a later *successful import or export of that store*, not on a setup event. A no-account setup failure (134400) is account state, not a dead delegate.

**Retryable CloudKit errors** (`CKError.h`; [TN3162](https://developer.apple.com/documentation/technotes/tn3162-understanding-cloudkit-throttles), 14 Aug: the container recovers from throttles on its own):
- **Temporary:** `networkUnavailable`, `networkFailure`, `serviceUnavailable`, `requestRateLimited`, `zoneBusy`, `serverResponseLost`.
- `limitExceeded` means split the batch, which the container does itself: neutral, not "storage full".
- `zoneNotFound` has no retry guidance: neutral, not "the app needs an update".
- `accountTemporarilyUnavailable`: wait for `CKAccountChanged` and never clear cached data. → B step 6.

**Stop Sharing** (CKShare docs; `UICloudSharingController.h`; Apple's custom-sharing-flow sample):
- The owner stops sharing by deleting the share. `UICloudSharingController` always offers the owner Stop Sharing, and there's no API to hide it (only `availablePermissions`).
- Apple's sample for a custom flow uses `fetchParticipants`, `addParticipant`/`removeParticipant` (which need `publicPermission == .none`) and `persistUpdatedShare`. → A step 2 uses the app's own members sheet on iPhone and iPad too, not the system sheet.
- `UICloudSharingController(preparationHandler:)` is deprecated since iOS 17 (replaced by `ShareLink` with `CKShareTransferRepresentation`). Don't add it.

**Stale shares** (`CKError.h` `serverRecordChanged`; `NSPersistentCloudKitContainer_Sharing.h`):
- Apple doesn't say to fetch the latest share before `persistUpdatedShare`. Its rule for a stale change tag is to merge into the server copy, so fetching the latest first is consistent with it. → A step 5.
- `share(_:to:)` fails if anything reached by deep traversal is already shared. → E step 2 (the restore supply link).
- `fetchShares(in:)` is synchronous and does no network work; main-thread safety isn't stated. → A step 4 moves it off the main actor anyway.

**App Intents launches** ([Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent), 11 Sep):
- Apple doesn't document that a background intent launch creates the `WindowGroup` scene or runs a view's `.task`, and says to register what intents depend on "as soon as possible" in `App.init()`.
- Don't rely on view `.task` for services Siri needs. → A step 1 starts the guard from where the shared stack is made as well as in `SiriHost.didSave`.
- Background intents get ~30 s on iOS.
- `openAppWhenRun` is deprecated at 26.0 for `supportedModes`, but the Assistant (18.0) keeps it. Not in scope.

**Purge and zoneless objects** (`purgeObjectsAndRecordsInZone(with:in:)` docs):
- The purge is by zone and says nothing of objects never assigned to one. → C step 3 deletes the waiting records explicitly before purging.

**Key-value `initialSyncChange`** ([didChangeExternallyNotification](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore/didchangeexternallynotification), 14 Aug):
- It means the first load from iCloud is still in progress, so don't write during it. Treat it as "re-read when a later change arrives", not as a server change.
- → E step 5 redraws on it but never publishes.
- `accountChange` replaces everything with the new account's values.

## Phase 1: Six fix agents (parallel)

- Who: the main session launches six agents in one message, each with `isolation: "worktree"`, in the background:

  | Agent | Type | Model, effort | Why |
  |---|---|---|---|
  | A: filing and share setup | `feature-phase-deep` | Opus, xhigh | A mistake misfiles records or breaks the share |
  | B: sync status | `feature-phase` | Opus, high | Mostly status logic, but it moves the history-purge gate |
  | C: Daybook Assistant sync | `feature-phase-deep` | Opus, xhigh | Leave and attaching can lose marks |
  | D: history, dedup, stack | `feature-phase-deep` | Opus, xhigh | Dedup deletes data |
  | E: names, shared writers, schema 17 | `feature-phase-deep` | Opus, xhigh | A schema change and backup format |
  | F: Remove Last Year | `feature-phase-deep` | Opus, xhigh | It deletes shared originals |

- **Every agent's prompt** says:
  - Read this plan's Decisions, the agent's own section below, and the report's matching entries. Read them by absolute path in `/Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/bug-hunt-report-ad32c2/`: agent worktrees start at the last pushed main, which lacks these two files.
  - Edit only the files it owns.
  - Build once before editing, with the prefix-mapping settings from `Cosmic Daybook/CLAUDE.md`.
  - Build only its scheme(s), through `Scripts/locked_xcodebuild.sh`.
  - Run only its `-only-testing:` suites, on its leased iOS simulator, through `~/.claude/bin/build-turn` with `-parallel-testing-enabled NO`. Never run macOS tests: the Mac test host opens Danny's live store.
  - If a changed file is also compiled into the Daybook Assistant (check `project.pbxproj`), build the `Daybook Assistant` scheme too, keeping its iOS 18.0 floor: no iOS 26/27 API without `#available`, and classic notifications rather than typed messages in shared files.
  - Add a focused test for each fix where the logic can be tested.
  - Commit on its branch with the attribution line.
  - Run `~/.claude/bin/sim-lease --done` before replying.
  - Reply in at most 15 lines: files changed, build and test results with counts, anything unresolved or done differently from the plan. No narrative.

### Agent A: filing and share setup
- Fixes: report #1, #3, #4, #11 (all four bullets), and the smaller "Share setup and filing" list:
  - the no-iCloud fallback queue
  - "No students are shared" on a nil read
  - the pin save result
  - the pre-pin re-file
- Owns:
  - `Siri/SiriHost.swift`
  - `AppCore/AppBootstrapping*.swift` (where the shared stack is made; not `AppBootstrapper.swift`, which is E's)
  - `Sharing/SharedStoreOrphanGuard.swift`
  - `Sharing/ClassroomSharingService.swift`, `+Setup.swift`, `+Members.swift`, `+Contents.swift`
  - `Sharing/ClassroomShareAttach.swift`
  - `Settings/Classroom/ClassroomSharingView.swift`, `ClassroomSharingViewParts.swift`, `ClassroomMembersSheet.swift`
  - `Sharing/CloudSharingControllerWrapper.swift`
  - `Backup/BackupService+Restoration.swift`
  - `Backup/Import/BackupEntityImporter+Students.swift`
- Steps:
  1. **Siri filing.** `SiriHost.didSave` starts the guard, queues the created records and flushes (pattern: `Daybook Assistant/Siri/AssistantSiriHost.didSave`). Also start the guard where the shared stack is first made (`AppBootstrapping.getSharedCoreDataStack` or `App.init`), so no background launch depends on a window's `.task` (Apple guidance › App Intents). Skip that start under `AppBootstrapping.isRunningUnitTests`, or the test host keeps a persisted waiting list between runs.
  2. **Stop Sharing on iOS.** It calls `removeAllMembers()` behind a confirmation dialog (the Mac's wording). The guide's iPhone and iPad stop using `UICloudSharingController`, whose Stop Sharing deletes the share and can't be hidden (Apple guidance › Stop Sharing). They use the app's own members sheet instead (`ClassroomMembersSheet`, made to work on iOS): look up, add, remove, `persistUpdatedShare`, and send the invitation link with `ShareLink` of the share URL. `CloudSharingControllerWrapper` goes if nothing else uses it. `handleSharingStopped` stays for a share stopped elsewhere.
  3. **The waiting list.**
     - Inserts are never trimmed in favor of updated-student entries: trim from the end, or keep inserts first.
     - The importer sets a student's enrollment fields only when they differ.
     - After a restore, the guard's list is cleared and setup's "add what's in no share" pass runs, if a pin and share exist and it's the lead guide.
  4. **The guard's flush.**
     - A timeout around each attach (reuse `CloudKitServerCheck.withTimeout`, or an equivalent) clears `flushTask` and leaves the records listed.
     - The guard doesn't flush while setup runs (a flag setup sets).
     - `flush()` uses the async `ClassroomShareAttach.classroomShare(inStoreWithIdentifier:...)` read.
  5. **Members.** `addMember`/`removeMembers` fetch the latest share (`ClassroomShareAttach.current`) before changing and saving it.
  6. **The smaller ones:**
     - Queue inserts even when `isCloudKitActive` is false; `flush()` waits until it's true.
     - `shareContents == nil` → "Couldn't check. Try again", not "no students".
     - Check the pin save, and stop setup with a plain message if it failed.
     - When the pin first arrives from another device, drop list entries created before the pin's date.
- Builds: `Cosmic Daybook` for the iOS Simulator and macOS (the members sheet), plus `Daybook Assistant` if `ClassroomShareAttach` or `ClassroomSharingService` changed.
- Tests: `SharedStoreOrphanGuardTests`, `ClassroomShareAttachLookupTests`, `ClassroomShareSelectionTests`, `ClassroomSharingListenerTests`, `ClassroomMemberErrorTests`, `ClassroomSharingWordingTests`, `SiriAttendanceTests`, `RestoreKeepsClassroomPinTests`, `BackupRestoreTransactionTests`, plus new tests:
  - Siri's save queues, and the guard starts without a window
  - Stop Sharing on iOS keeps the share
  - an overflow keeps inserts
  - a timed-out attach frees the guard
  - setup holds the guard

### Agent B: sync status
- Fixes: report #6 (the first three bullets), #7, and the smaller "Sync status and monitoring" list, except the account ID (E).
- Owns:
  - `Services/Sync/CloudKitSyncStatusService.swift` and all its extensions
  - `SyncRetryLogic.swift`, `CloudKitStoreHealth.swift`, `CloudKitHealthCheck.swift`, `SyncStoppedAdvice.swift`, `SyncEventLogger.swift`
  - `AppCore/Persistence/CloudKitConfigurationService.swift`
  - `Components/Shared/SyncStatusIndicator.swift`
  - `Settings/Sync/*`
  - `AppCore/AppServicesLauncher.swift`
  - `Services/MCPServer/MCPNotebookTools+SyncStatus.swift`
  - `Services/Sync/PersistentHistoryProcessor.swift`: the purge function only
  - the three last-error keys in `UserDefaultsKeys.swift`
- Steps:
  1. **What counts as synced.**
     - A remote change no longer stamps success, clears errors, zeroes pending or cancels the save timeout. Only successful import/export events do.
     - The remote change still feeds the import overlay.
  2. **Retries.**
     - They don't call `syncNow()`'s success path, log "You tapped Sync Now" or stamp a sync.
     - `retryTask` is cleared when it ends.
     - Offline waits don't use up attempts.
  3. **The toolbar dot** follows `storeHealth.mostSevereFailure` and the stopped flag.
  4. **Events at launch.** Add `beginEarlyEventCapture(for:)`: it starts the CloudKit event stream for a stack before `configure` and hands buffered events to the handlers once `configure` runs. Phase 2 wires the call (Decisions › No agent calls code another agent adds). `configure` also makes its event stream at once; only the store-change listener waits 2 s. Test it by feeding a failed setup event before `configure`.
  5. **The stopped flag.** `mirroringDelegateFailed` clears only when the store that set it has a later *successful import or export*, never on a setup event alone (Apple guidance › Setup events). A no-account (134400) or network setup failure doesn't set it.
  6. **The smaller ones:**
     - The import overlay is keyed off `FirstDownloadGate.isPending()`.
     - Signed out reads as "iCloud isn't available. Sign in…". On an account change, reset this service's per-account state: sync dates, flag, health.
     - Add the retryable codes listed under Apple guidance (incl. `serverResponseLost`, `zoneBusy`) to the temporary set.
     - `.limitExceeded`, `.zoneNotFound` and `.tooManyParticipants` get a neutral category.
     - Scope the error keys.
     - Keep the last export start per store, and have `purgeOldHistory` purge each store with `affectedStores` and its own date.
- Builds: `Cosmic Daybook` for the iOS Simulator and macOS, and `Daybook Assistant` (`PersistentHistoryProcessor`, `CloudKitConfigurationService` and `UserDefaultsKeys` compile into it).
- Tests: `AssistantHistoryTrimTests`, `AssistantSyncJoinLeaveTests`, `CloudKitStoreHealthTests`, `SyncStoppedAdviceTests`, `PersistentHistoryAdvanceTests`, `PersistentHistoryStoreCursorTests`, plus new tests:
  - a remote change doesn't stamp success
  - a retry doesn't log a tap
  - the flag clears on success
  - the dot shows on a store failure
  - purge per store

### Agent C: Daybook Assistant sync
- Fixes: report #6 (the fourth bullet), #8, and the smaller "Daybook Assistant" list, except the name-row internals (E).
- Owns:
  - `Daybook Assistant/Sync/*`
  - `Daybook Assistant/Onboarding/AssistantNameStore.swift`
  - `Daybook Assistant/Siri/AssistantSiriHost` (and any Siri host file it needs)
  - `Daybook Assistant/AssistantTabs.swift`
  - `Cosmic Daybook/Services/Sync/UnsentChangesKeepAlive.swift`
  - `Cosmic Daybook/Attendance/Store/CDAttendanceStore+ClassroomShare.swift`
  - `Daybook Assistant Tests/UnsentChangesKeepAliveTests.swift`
- Steps:
  1. **The keep-alive's unsent rule.** It tracks the newest save. In the Assistant, only saves that touched the shared store count.
  2. **"All marks sent".** The last shared save is recorded for the whole app (beside the keep-alive, Siri included), not in `AssistantSyncStatusView`. The status reads "Sending…" while the attacher's waiting list isn't empty (add a read-only `pendingCount`; the list is private, in UserDefaults), and reads export starts from an app-lifetime recorder (`AssistantHistoryTrim.recordExports` already tracks them).
  3. **Leave.** It waits for the running attach pass, deletes the waiting records from the shared store, clears `Assistant.pendingShareAttach` and cancels the retry, then purges. `AssistantClassroomLocalState.forget` clears the list.
  4. **Every save files its records.** `AssistantSave` hands every share-type object in the context's inserts to the attacher.
  5. **A dropped stop report.** If it's ignored while the container is still the open one, re-check after the phase settles, or set `sendingStopped`.
  6. **Rebuilds.** They await `AssistantShareAttacher.shared.waitUntilIdle()` (add it if missing) instead of sleeping 300 ms. "No shared store" means try again, not done.
  7. **Two zones.** In `AssistantShareAttacher` only (`ClassroomShareAttach` is A's), after attaching, confirm the zone `fetchShares(matching:)` returns is the pinned one. If not, keep the record counted as unsent and log it, never move it.
  8. **Name-row call sites.** Call `writeWaitingName` after `.didJoinClassroom`, after leaving the Sample Class, and on return to the foreground. On `.CKAccountChanged`, C fetches the user record ID itself (`CloudKitConfigurationService.container.userRecordID()`) and compares it with the one saved before. If it changed, block writes until it's re-read, and ask for her name again. Don't call anything E adds; E makes `ClassroomIdentity` refresh its own saved ID.
- Builds: `Daybook Assistant`, plus `Cosmic Daybook` for the iOS Simulator (shared files).
- Tests: `UnsentChangesKeepAliveTests` (rewrite `firstSaveCounts`), `AssistantShareAttacherTests`, `AssistantShareAttacherStackTests`, `AssistantSyncJoinLeaveTests`, `AssistantSiriTests`, `AssistantHistoryTrimTests`, `AssistantShareScopeTests`, plus new tests:
  - the A/export/B case
  - Leave clears the list
  - a Siri save marks unsent
  - a wrong zone stays unsent

### Agent D: history, dedup and the stack
- Fixes: report #2, and the smaller "History, duplicates and the stack" list. This includes the report's dedup-without-sync item, which also covers Remove Last Year's guard finding.
- Owns:
  - `Services/Migrations/DataCleanupService+Deduplication*.swift`
  - `+DeduplicateLessons.swift`, `+DeduplicateWork.swift`, `DedupShareBoundary.swift`, `MigrationRunner.swift`
  - `Work/Models/WorkModelEntity.swift`
  - `Services/Sync/DeduplicationCoordinator.swift`
  - `AppCore/Persistence/CoreDataStack.swift`, `+Stores.swift`, `DatabaseInitializationService.swift`, `DatabaseErrorCoordinator.swift`
  - `Backup/Core/BackupChangeTracker.swift`, `Backup/Core/AutoBackupManager.swift`
  - the Reset Local Cache request key in `UserDefaultsKeys.swift`
  - `Settings/DataManagement/DatabaseMaintenanceCard.swift`
- Steps:
  1. **Same-`id` merges.** Track (enrollments and steps), Lesson (attachments and sample works), TodoItem (subtasks) and CommunityTopic (solutions and attachments) each move the duplicate's children onto the survivor before the delete.
  2. **Work duplicates.** `mergeWorkModel` relinks the duplicate's text-only check-ins (`workID == id AND work == nil`) to the canonical before the delete, or `prepareForDeletion` skips the sweep while another live WorkModel has the same `id`.
  3. **Tie-break.** When `createdAt` ties, skip the group if any copy has no CloudKit record yet (`record(for:)` nil) or all copies arrived in the last few minutes. A newer-record rule isn't stable across devices.
  4. **Dedup without sync.** It doesn't delete in share-type groups (and skips the id pass) when the container isn't mirroring.
  5. **Re-download from the error screen.** `resetLocalDatabase()` calls `CoreDataStack.clearLocalCacheResetFlags(in:)`.
  6. **The Reset Local Cache request.** Its key is scoped by environment (also in `Settings/DataManagement/DatabaseMaintenanceCard.swift`'s `@AppStorage`). On the Mac, `prepareOnDiskStores` skips the reset while another copy of the app runs, with its own `#if os(macOS)` `NSRunningApplication` check. `anotherCopyBlocker` is F's and isn't compiled into the Assistant.
  7. **The single-store fallback.** It gets no `PersistentHistoryProcessor`.
  8. **Auto-backup baseline.** It takes its history token before collecting rows and passes it to `recordBackupPoint`. Automatic backups wait while `FirstDownloadGate.isPending()`.
- Builds: `Cosmic Daybook` for the iOS Simulator and macOS, and `Daybook Assistant` (`CoreDataStack*` and `UserDefaultsKeys` compile into it).
- Tests: `AssistantSyncJoinLeaveTests`, `DeduplicationMergeTests`, `DeduplicationScopeTests`, `DeduplicationFootprintTests`, `DedupShareBoundaryTests`, `OrphanStudentGraceTests`, `PracticeSessionDeduplicationTests`, `SupplyResourceDeduplicationTests`, `PersistentHistoryTokenScopeTests`, plus new tests:
  - each same-`id` merge keeps the children
  - the work-duplicate check-ins survive
  - no deletes without mirroring
  - the backup token is taken first

### Agent E: names, shared writers and schema 17
- Fixes: report #10, the smaller "Names and other shared records" list, the account-switch ID (from "Sync status"), the restore supply link (#5), and staple history names via schema 17.
- Owns:
  - `Sharing/ClassroomNames.swift`, `ClassroomPersonEntity.swift`, `ClassroomIdentity.swift`
  - `Settings/Classroom/ClassroomYourNameCard.swift`
  - `Attendance/Email/*` (incl. `AttendanceEmail+Prefs.swift`, `AttendanceEmailLog.swift`)
  - `Attendance/Rules/AttendanceRules.swift`
  - `AppCore/AppBootstrapper.swift` (the launch email write)
  - `Services/MCPServer/MCPNotebookTools+Attendance.swift`
  - `Services/Sync/SyncedPreferencesStore.swift`
  - `Supplies/*`, `Daybook Assistant/Restock/AssistantRestockHistorySheet.swift`
  - `CosmicDaybook.xcdatamodeld`
  - `AppCore/Persistence/CoreDataStack+SchemaVersion.swift`
  - `Backup/BackupEntityTable.swift`, `Backup/ModelRowKinds.swift`, `Backup/BackupRestoreRun+LaterTypes.swift`, and the backup format-version constant (`Backup/Archive/BackupWriter.swift:99`)
- Steps:
  1. **The front-desk email settings row.** `AttendanceEmail.shareSettings` runs only from an explicit edit: the settings screen's change handler compares against the last value it wrote, not on appear. Drop the launch call in `AppBootstrapper`.
  2. **Restore links.** Supply history restores by `supplyID` only (no `supply` parent link). A `ClassroomPerson` row with a newer existing `modifiedAt` is skipped on a Merge restore.
  3. **`ClassroomNames`:**
     - Choose the guide by the owner's record name when known.
     - Scope `myRows` and the fold to the pinned classroom.
     - Fold only after this launch's first successful import.
     - `writeWaitingName` does nothing until the device has a membership and the class has downloaded.
  4. **`ClassroomIdentity` re-reads the record ID itself on `.CKAccountChanged`** (clear the saved ID, fetch it again). C handles the Assistant's name prompt.
  5. **The MCP sender name.** `attendance_for_day` names the sender by current name (`AttendanceEmailLog.senderName` through the list, falling back to the stamped one). "another assistant" becomes "an assistant" on the guide's screens (by `viewerRole`). `SyncedPreferencesStore` re-reads and redraws on `initialSyncChange` (bumps `changeCount`) but publishes nothing during it (Apple guidance › Key-value).
  6. **Schema 17**, per Decisions:
     - `CDSupplyTransaction.changedByID` (optional string, default `""`), stamped from `RestockAuthor.recordName` (real IDs only, never `__defaultOwner__`).
     - The history sheets in both apps show the current name, with the stamped name as fallback.
     - `currentSchemaVersion` 16 → 17; backup v38 → v39, with a round-trip test.
     - Grep `"SupplyTransaction"` for every list the type sits in.
- Builds: `Cosmic Daybook` for the iOS Simulator and macOS, and `Daybook Assistant` (the model and the shared files).
- Tests: `ClassroomNamesTests`, `ClassroomNamesEdgeCaseTests`, `ClassroomNamesNotebookTests`, `ClassroomNamesWordingTests`, `ClassroomIdentityTests`, `ClassroomPersonMigrationTests`, `AttendanceEmailLogTests`, `AttendanceEmailPreferencesTests`, `SyncedPreferencesStoreTests`, `SchoolYearSyncTests`, `RestockStapleTests`, `RestockWhoLineTests`, `RestockSplitStoreTests`, `BackupRestockRoundTripTests`, `BackupClassroomNamesRoundTripTests`, `BackupRestoreEquivalenceTests`, `CoreDataSchemaVersionTests`, `SchemaCoherenceCacheTests`, `BackupFieldCoverageTests`, `BackupGoldenOutputTests`, `BackupRoundTripTests`, `BackupSparseRowTests`, `MCPClassroomToolsTests`, and the Assistant's `AssistantRestockTests`, `AssistantRestockWordingTests`, plus new tests:
  - no launch write of the settings row
  - the supply link not set on restore
  - the fold scoped to the class
  - `changedByID` round-trips and renames show

### Agent F: Remove Last Year
- Fixes: report #9 and the smaller "Remove Last Year" list. The dedup-guard item is D's.
- Owns:
  - `Sharing/ClassroomShareRelease.swift` and all `+` files
  - `Sharing/ClassroomShareExportActivity.swift`
  - `Services/Sync/CloudKitServerCheck.swift`
  - `Settings/Classroom/ClassroomReleaseModel.swift`, `ClassroomLastYearCard.swift`, `ClassroomReleaseSheet.swift`
  - `Backup/BackupRecordCheck.swift`
  - `docs/Technical notes/CloudKit/CLOUDKIT_GUIDE.md` §2: the `BackupRecordCheck` drift
- Steps:
  1. **The start date.** `start()` refuses when the fresh plan's cutoff differs from the preview's, or when it holds records the preview didn't, and re-runs the just-before-start guard on the fresh cutoff. It shows the new preview.
  2. **One run at a time.** A process-wide "release running" flag. `blocker` refuses while it's set, and the card shows "running", not "stopped partway".
  3. **Unconfirmed deletes.** Append to `awaitingGone` instead of replacing it (or finish it before the first batch). `finishStopped` nudges an export.
  4. **The counts.**
     - The card counts each id once.
     - The "older marks" line says whether the student belongs.
     - The report counts deleted-elsewhere records separately.
     - The card's `IN` predicate matches ids case- and space-insensitively.
  5. **Errors.** Core Data/Cocoa errors get their own plain message ("Something changed while this ran. Run it again.").
  6. **What the backup can't carry.** Records with no date or a malformed `studentID` are left out of the plan and named in the preview.
  7. **Timeouts and timing.**
     - `serverSummary` gets `withTimeout`.
     - The `saved` timestamp is taken after `save()` returns.
     - `stopReason` also checks `anotherCopyBlocker`.
- Builds: `Cosmic Daybook` for macOS and the iOS Simulator.
- Tests: `ClassroomShareReleaseTests`, `ClassroomShareReleaseVanishedTests`, `CloudKitServerCheckTests`, `ClassroomShareScopeTests`, plus new tests:
  - a changed cutoff refuses
  - a second run is refused
  - `awaitingGone` accumulates
  - the counts

### Phase 1 overall
- Cost: ~8–12% of weekly (six bug-fix agents, five deep at xhigh and one at high. A, C, D and E are large, ~2% each; B and F ~1% each. E carries the schema).
- Done when:
  - All six agents have replied with their scheme builds clean and their suites green (counts in the reply).
  - Each branch has its commits, and each agent's leased simulator is shut down.
  - No agent edited a file outside its list without saying so.
- Hand off: no. Phase 2 needs the six branch names, which are in this session.

## Phase 1b: Re-scope and relaunch after the data-model plan
- Who: main session (Opus 5.5, high) to re-scope, then agents as in Phase 1 (same types and models), fewer and narrower.
- Starts when: `docs/Plans/Plan - Data model and launch repair fixes.md` says `> **Done <date>** (<commit>).` on main (check with git, never from memory). Read the plan usage first: at 2026-10-05 22:55 the week was 75% used (25% left until Sun Oct 11, 4 PM EDT). If less than ~10% is left, wait for the reset.
- Steps:
  1. **Merge.** Merge main into `claude/sync-sharing-bug-hunt-08dddc` (it already holds agent C). Resolve conflicts in C's files in favor of keeping both fixes.
  2. **Compare the two lists.** For each entry in this plan's report, read the data-model plan and its squash diff, and mark it "fixed by data-model `<commit>`" or "still to fix". Expect these to be covered: #1 Siri, #4 the 2,000 cap, #2 (children and work check-ins), the error screen's Re-download, parts of #11 and the history items. Record the result as a table in this plan, under this phase.
  3. **Rebase the WIP branches.** Rebase A, D and E (`worktree-agent-aaa0baf22bedd002f`, `-a3a09e5b116165d2f`, `-a2e5fe33fff81540a`) onto the new main in fresh agent worktrees. Drop hunks for findings marked fixed; keep the rest as each agent's starting point.
  4. **Relaunch.** Start narrowed agents for A, B, D, E and F, each told: start from the rebased WIP branch, fix only the "still to fix" entries in its section, and treat the data-model plan's changes in the same files as the base, never undoing them. B and F start from main. Same rules, builds and tests as Phase 1; add any suites the data-model plan created for the same files.
- Cost: re-estimate at step 2 from what's left (roughly 1% per narrowed agent, plus ~0.5% for the comparison).
- Done when: every report entry is either fixed by data-model (commit named) or fixed by an agent here. Each relaunched agent replies with builds clean and suites green. The branches are ready for Phase 2.
- Hand off: yes, if the data-model plan lands after this session has ended. Starter: "Model: Opus 5.5, effort: high" then "In /Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/bug-hunt-report-ad32c2, read docs/Plans/Plan - Sync and sharing fixes.md and do Phase 1b, then Phase 2. Follow its Starting a phase and Ending a phase steps."

### Comparison with the data-model fixes (step 2, done 2026-10-06 09:40 against its branch at `a6c5009c`)

A Sonnet reviewer read the data-model branch's code; Claude spot-checked the Siri and front-desk verdicts.
- **Counts:** fixed there 11, partly 1, clashing 4, still to fix 42 (10 of them C's, already done).
- **Relaunch scope:**
  - **A:** #3, #11a, #11c, the nil-read wording, the pin-save result, the pre-pin re-file. Steps 1 and 3 are dropped; step 3's post-restore full pass would be a sweep.
  - **B:** #6a–c, #7a–b and the smaller sync-status list, but not the purge (fixed there).
  - **D:** the Replace-restore tie-break, the auto-backup token, the single-store processor, backups during a first download. Steps 1, 2, 4, 5 and 6 are dropped.
  - **E:** #5, the guide choice (partly), fold gating, the `writeWaitingName` guard, Merge-restore names, schema 17, the MCP sender, the settings redraw, "an assistant", the `ClassroomIdentity` refresh. Step 1 is dropped (#10 is fixed there).
  - **F:** everything.
- **Clashes to adapt:**
  - B wires `beginEarlyEventCapture` from `startStoreObservers` (`AppBootstrapping+ErrorHandling.swift`), since `getSharedCoreDataStack` no longer makes the stack.
  - A's attach timeout must not release `ClassroomShareAttachLock` while an abandoned `share(_:to:)` may still run.
  - F's `awaitingGone` change must also fix the new `catch` in `+Run.swift` that clears the whole list.
  - F's `saved` stamp moves after `deleteOriginals(_:keeping:context:)` returns.
- **The WIP branches** (A, D, E) are reference only. The data-model squash rewrote most of their files, so the agents re-implement on the new main rather than rebase.

<details><summary>Full table</summary>

### Sync-and-sharing findings vs the data-model branch

Compared against `claude/data-model-launch-repairs-063ae8` at `a6c5009c` (base `3fda274e`). Paths are under `Cosmic Daybook/` and line numbers are on that branch unless marked "base". Plan sections are from `docs/Plans/Plan - Sync and sharing fixes.md`. Agent C is already merged into the sync branch and shares no file with the data-model branch, so its findings are marked "C (done)". For them the data-model branch changes nothing.

Verdicts: FIXED = the data-model branch fixes it as the finding needs. PARTLY = part fixed. NOT = untouched or fixed in a way that leaves the bug. CONFLICT = the bug is still there, and the planned fix collides with code the data-model branch changed (the adaptation is in the last column).

#### Fix first

| Finding | Verdict | Evidence | What's left / which agent |
|---|---|---|---|
| #1 Siri mark made while the notebook is closed | FIXED | The guard now starts when the shared stack loads, for any caller: `AppCore/AppBootstrapping+SharedStack.swift:98` passes `didLoad: startStoreObservers`, which calls `SharedStoreOrphanGuard.shared.start` (`AppBootstrapping+ErrorHandling.swift:14-18`). The save path is `Siri/SiriAttendance.swift:248` → `Siri/SiriHost.swift:86-88` → `Sharing/SharedStoreOrphanGuard.swift:121-127` (`siriDidSave`). That starts the guard (idempotent), keeps only share-type records that are in the private store and have permanent IDs, calls `handleSaved` (queues and flushes), then `waitUntilIdle()`. Both halves hold: the guard starts, and the records are queued. Tests: `SiriClassroomShareQueueTests:18`, `SharedStackLoadTests:16`. Commits: 1A `4e8f640c`, 1D `10df3b20`, tests `5d73e257`, `c92455d8`. | Nothing. Drop A step 1, including the "skip under isRunningUnitTests" note: an in-memory test stack never calls `didLoad`. |
| #2 Duplicate cleanup throws away children (Track, Lesson, TodoItem, CommunityTopic, work check-in sweep) | FIXED | The generic pass calls each type's `merge` before `context.delete` (`Services/Migrations/DataCleanupService+Deduplication.swift:122-124, 143-148`), and `mergeNSSetRelationship` now moves every child, even one with the survivor's id (`:193-213`). Track: `mergeTrack` moves steps and enrollments (`+TrackTitleMerge.swift:264-285`). Lesson: `mergeLesson` moves attachments and sample works (`+DeduplicateLessons.swift:105-111`), plus notes and assignments. TodoItem: `mergeTodoItem` moves subtasks (`+DeduplicateRecords.swift:253-264`). CommunityTopic: `mergeCommunityTopic` moves solutions and attachments (`:266-287`). Work: `mergeWorkModel` moves the check-ins and `linkIDOnlyCheckIns` relinks text-only ones (`+DeduplicateWork.swift:82-98`). `CDWorkModel.prepareForDeletion` skips its text-only sweep while another live row has the same id (`Work/Models/WorkModelEntity.swift:49-65`). Tests: `DedupChildRescueTests` (lines 44, 59, 75, 99, 131, 160), `DedupSameIDChildTests:19`. Commit `704dfdad`. | Nothing. Drop D steps 1 and 2. |
| #3 Stop Sharing on iPhone/iPad deletes the share, setup then refuses | NOT | `Settings/Classroom/ClassroomSharingView.swift` is only +3 lines for the catch-up card. The iOS Stop Sharing button still does `showingSharingSheet = true` (system sheet). `ClassroomSharingViewParts.swift`, `ClassroomMembersSheet.swift`, `CloudSharingControllerWrapper.swift` and `ClassroomSharingService+Members.swift` are untouched. The setup refusal is still at `Sharing/ClassroomSharingService+Setup.swift:141-142` (`shareStillSyncing`). | Agent A step 2, whole. When rebasing A's WIP onto the data-model branch, keep `setUpClassroomSharing` inside `ClassroomShareAttachLock.shared.run` (+Setup:45). |
| #4 Restore overflows the 2,000 waiting list and drops the restored records | FIXED | `Sharing/SharedStoreOrphanGuard+WaitingList.swift:44-60`: `add` never drops. `prune` (`:121-151`) first removes deleted, already-shared and out-of-scope entries. With a pin it logs and drops nothing (`:144-147`). It drops the oldest only when there is no pin (`:148-150`). A save that updated a student queues only the student, not all her attendance (`+Records.swift:35-43`), so Merge-restore updates add one entry per student. Tests in `ClassroomShareWaitingListTests`: `noCapWhilePinned:91`, `goneRecordsLeaveBeforeWaitingOnes:109`, `editedStudentQueuesHerAlone:69`. `BackupEntityImporter+Students.swift` is untouched (it still sets every field) but is now harmless. | Nothing required. Residual: with no pin yet, past 2,000 the oldest still drop (`:148-150`), and setup attaches everything anyway. Drop A step 3 entirely. Its third bullet (a full filing pass after a restore) is the "records that look unshared" sweep both plans rule out. |
| #5 Merge restore can re-share a staple through the `supply` link | NOT | `Backup/BackupRestoreRun+LaterTypes.swift:256-260` still passes `parents: ["supply": …]`, and `Backup/ModelRowKinds.swift:197-201` still has `ParentLink(key: "supplyID", relationship: "supply")`. Neither file is in the data-model diff. | Agent E step 2, whole (restore history by `supplyID` only). |
| #6a Own saves count as news from iCloud | NOT | The remote-change handler in `Services/Sync/CloudKitSyncStatusService+EventHandlers.swift` (~129-153) is untouched. The data-model branch edited only the success branch (~288-300, `recordWatermark`). | Agent B step 1. |
| #6b Automatic retry pretends to be Sync Now | NOT | `CloudKitSyncStatusService.swift` and `SyncRetryLogic.swift` are untouched. | Agent B step 2. |
| #6c Toolbar dot ignores per-store health | NOT | `Components/Shared/SyncStatusIndicator.swift` is untouched. | Agent B step 3. |
| #6d Assistant "All marks sent" misses Siri marks | NOT (C) | The Assistant's `AssistantSyncStatusView` and `UnsentChangesKeepAlive` are not in the data-model diff. | C (done in `2f163a80`). No overlap. |
| #7a Blind start: a setup failure at launch goes unseen | CONFLICT | Not fixed. Nothing captures `.setup` events before `configure`. The data-model branch's early subscription (`startStoreObservers` → `CloudKitSyncStatusService.watchForFirstDownload(on:)`, `Services/Sync/CloudKitSyncStatusService+FirstDownload.swift`) only opens the first-download gate. Conflict: the sync plan's seam (B adds `beginEarlyEventCapture(for:)`, Phase 2 calls it from `AppBootstrapping.getSharedCoreDataStack`, A's file) is obsolete. `getSharedCoreDataStack` is now a synchronous accessor that never creates the stack (`AppBootstrapping+SharedStack.swift:68-82`). The stack is made in `openSharedStack` (`:91-104`). | Agent B (+ Phase 2 wiring). Call `beginEarlyEventCapture` from `startStoreObservers` (`AppBootstrapping+ErrorHandling.swift:14-18`), the one hook every launch path runs: window, Siri, MCP. Reuse or sit beside the first-download watch's `.eventChanged` subscription. In-memory test stacks never reach it, so test the capture directly. |
| #7b Stopped flag never clears | NOT | `+EventHandlers.swift:~412` still sets `mirroringDelegateFailed`. Nothing on the branch clears it. New code only reads or sets it (`ClassroomAttendanceCatchUp.swift:102, 133`, guard `:168, 226`). | Agent B step 5. Hook: dm's `recordWatermark(type:startDate:storeIdentifier:)` (`Services/Sync/ImportWatermark.swift:93-109`) already runs for every successful non-setup event with a store id, so the "same store's next success" clear can go there. |
| #8a Leave drops a mark (keep-alive tracks the first unsent save) | NOT (C) | `Services/Sync/UnsentChangesKeepAlive.swift` is untouched by the data-model branch. | C (done). No overlap. |
| #8b Leave keeps the waiting list for the next class | NOT (C) | The data-model branch's `clearLocalCacheResetFlags` clears `classroomSharePendingAttach` only for Reset Local Cache and Re-download, not for Leave. `AssistantBootstrapper+Class.swift` is untouched. | C (done). No overlap. |
| #9 Remove Last Year re-plans with a start date the guide never saw | NOT | `Settings/Classroom/ClassroomReleaseModel.swift` is untouched. | Agent F step 1. Note: `ClassroomShareScope` gained `isProvisional` (`Sharing/ClassroomShareScope.swift:30-48`), and its default init is now `init()`. F's "fresh cutoff differs" check may also compare `isProvisional`. |
| #10 Launch overwrites the shared front-desk email settings with stale ones | FIXED | Launch calls `AttendanceEmail.shareSettingsIfMissing` (`AppCore/AppBootstrapper.swift:199`; `Attendance/Email/AttendanceEmail+Prefs.swift:77`; `AttendanceEmailLog.saveSettingsIfMissing` at `:255`, which writes only when no row exists and the role is lead guide). The settings screen writes only after an edit (`Attendance/Email/AttendanceEmail.swift:98-112`): `seenSignature` (`:29, 106-110`) is recorded on first appearance with no write. No other launch caller remains. Test: `AttendanceEmailSettingsLaunchTests`. | Nothing. Drop E step 1; redoing it would fight `seenSignature`. Residual: a device with no row in the share and empty prefs can write empty recipients once, but there is no row to overwrite. |
| #11a One stuck attach stops filing until relaunch | CONFLICT | Not fixed. There is no timeout in `Sharing/SharedStoreOrphanGuard.swift:141-156` or in `ClassroomShareAttach.swift`; `flushTask` is still cleared only when the pass returns. Conflict: dm's `flush` holds `ClassroomShareAttachLock` for the whole pass (`SharedStoreOrphanGuard.swift:177-178`, `defer release`). A timeout that abandons a hung `share(_:to:)` and then releases the lock lets setup or the one-time step start attaching beside the still-running call, which the lock exists to prevent. | Agent A step 4. Put the timeout around the attach, clear `flushTask` and leave the entries listed. Do not release the lock while the abandoned call may still run: keep the lock held until it returns, or make setup report "another pass is still running" rather than wait. |
| #11b Setup and the guard attach the same records at once | FIXED | New `Sharing/ClassroomShareAttachLock.swift:11-40`. Setup runs inside it (`ClassroomSharingService+Setup.swift:45`), the guard acquires it (`SharedStoreOrphanGuard.swift:177-178`), and so does the one-time step (`Settings/Classroom/ClassroomAttendanceCatchUp.swift:119`). Setup forgets only the entries it found, except failures (`+Setup.swift:56, 100-102`). Every attach call gets the latest share and re-checks "unshared" before the first chunk too (`ClassroomShareAttach.swift` ~117-165, `stillOutside` ~234-243). Tests: `ClassroomShareAttachPassTests`, `ClassroomShareSetupListTests`. | Nothing. Drop the "flag setup sets" in A step 4; use the lock. |
| #11c Mac members sheet saves a possibly old copy of the share | NOT | `Sharing/ClassroomSharingService+Members.swift` is untouched. | Agent A step 5 (`ClassroomShareAttach.current`). |
| #11d Each new mark costs a share read on the main thread | FIXED | `SharedStoreOrphanGuard.swift:186-188` uses the async `ClassroomShareAttach.classroomShare(inStoreWithIdentifier:…)`, whose `shares(...)` is `@concurrent` (`ClassroomShareAttach.swift:62-86`). | Nothing for the per-mark path. Drop that bullet of A step 4. (Setup's `container.fetchShares(in:)` at `+Setup.swift:135` is still synchronous, but it is not the per-mark path.) |

#### Smaller findings

### Sync status and monitoring

| Finding | Verdict | Evidence | What's left / which agent |
|---|---|---|---|
| After Reset Local Cache the "Syncing from iCloud…" overlay never shows | NOT | `CloudKitSyncStatusService.swift` is untouched. `clearLocalCacheResetFlags` (`AppCore/Persistence/CoreDataStack+Stores.swift:275-292`) clears the waiting list, history tokens and repair flags, but not `cloudKitLastSuccessfulSyncDate`. | Agent B step 6, bullet 1 (key the overlay off `FirstDownloadGate.isPending()`). The gate now also opens at once with no iCloud account (`FirstDownloadGate.nothingWillDownload`), so keep that in mind. |
| Signing out still reads "iCloud sync is on"; an account switch keeps the old record ID and sync dates | NOT | `CloudKitHealthCheck.swift` and `Sharing/ClassroomIdentity.swift` are untouched. The data-model branch checks the account only to decide the first-download gate. | B (signed-out wording and per-account reset); E step 4 (`ClassroomIdentity` re-reads the ID on `.CKAccountChanged`). The Assistant side is C (done). |
| `.serverResponseLost` and `.zoneNotFound` read as "stopped" | NOT | `CloudKitStoreHealth.swift` is untouched. | Agent B step 6. |
| `.limitExceeded` shows as "iCloud storage is full" | NOT | `AppCore/Persistence/CloudKitConfigurationService.swift` only gained `nonisolated` on two statics (`:21, :23`). | Agent B step 6. |
| Saved last-error keys not scoped by environment | NOT | `AppCore/Constants/UserDefaultsKeys.swift:25-31` is unchanged. The data-model branch edited only the Reset Local Cache key (`:211`), so there is no textual clash with B. | Agent B step 6. |
| One export date guards history purging for both stores | FIXED | `Services/Sync/PersistentHistoryProcessor+Purge.swift:39-81` purges each store with `affectedStores` behind its own `exportStarts` date. `recordExportStart` (`:91-108`) keeps one date per store and ignores future dates. It is fed from `+EventHandlers.swift:293` → `ImportWatermark.swift:93-109`. The old global key is no longer written. Tests: `PersistentHistoryProcessScopeTests`, `ImportWatermarkTests`. Commit `10df3b20`. | Nothing. Drop B's purge step. `+Purge` is not compiled into the Assistant, which keeps `AssistantHistoryTrim`. |

### Daybook Assistant

| Finding | Verdict | Evidence | What's left / which agent |
|---|---|---|---|
| Status line sticks on "Sending to iCloud…" after a visit to Restock | NOT (C) | `AssistantSyncStatusView` untouched by the data-model branch. | C (done). |
| A record written by another screen's save is never handed to the filing list | NOT (C) | `Sync/AssistantSave.swift` untouched. | C (done). |
| A "sync stopped" report that arrives while starting or leaving is dropped | NOT (C) | `AssistantShareAttacher.swift` untouched. | C (done). |
| Her name row: written at launch when not in a class, not rewritten after Leave and re-join, Sample Class or offline name only at next cold launch | NOT | `Onboarding/AssistantNameStore.swift` and `ClassroomNames.writeWaitingName` (`Sharing/ClassroomNames.swift:~99-125`) are unchanged by the data-model branch. | C did the call sites (done: `AssistantBootstrapper+Names.swift`). E still owns the `writeWaitingName` guard "no membership or class not yet downloaded" (E step 3, bullet 4). |
| Leave warns about unsent marks right after joining | NOT (C) | `UnsentChangesKeepAlive` untouched. | C (done). |
| Stack rebuild sleeps 300 ms; a pass with no shared store drops its list | NOT (C) | `AssistantBootstrapper.swift` and `CDAttendanceStore+ClassroomShare.swift` untouched. The data-model branch edited only call sites of `SiriHost.stack()` in the Assistant (`AssistantSiriHost`, `AssistantAttendanceIntents`, `AssistantSiriRestock`, `SupplyAppEntity`). | C (done). |
| With two zones in her shared store a new mark can land in the wrong one and still count as filed | NOT (C) | `ClassroomShareAttach.swift:106-113` (base) is unchanged in the lines that matter. The data-model branch added `Steps` and the first-chunk recheck but no zone check. | C (done, `AssistantShareAttacher+Zone`). |

### Share setup and filing

| Finding | Verdict | Evidence | What's left / which agent |
|---|---|---|---|
| Records made during a "no iCloud" fallback launch are never queued | FIXED | `SharedStoreOrphanGuard.swift:109-114` (`handleSaved`) no longer checks `isCloudKitActive` (base `:125` did); `flush` waits for it (`:159`). Test: `ClassroomShareWaitingListTests.queuedWithSyncOff:52`. | Nothing. Drop that bullet of A step 6. |
| Manage Sharing says "No students are shared yet" when iCloud didn't answer | NOT | `Sharing/ClassroomSharingService+Setup.swift:183` (`shareForInvitations`): `(contents?.inShare["Student"] ?? 0) > 0`, so a nil answer throws `shareHasNoStudents`. | Agent A step 6. |
| Setup ignores whether saving the pin worked | NOT | `+Setup.swift:168` still `_ = repo.save(reason: "Pin classroom share")`. | Agent A step 6. |
| After setup on the Mac, the iPad can re-file records it queued before the pin arrived | NOT | `flush` (`SharedStoreOrphanGuard.swift:158-196`) still attaches whatever local metadata calls unshared. Nothing drops entries older than the pin. dm's `isProvisional` handling keeps out-of-scope entries and is unrelated. | Agent A step 6, last bullet. Keep it inside the new `flush` (it holds the lock). |

### Remove Last Year

| Finding | Verdict | Evidence | What's left / which agent |
|---|---|---|---|
| Two runs at once; nothing marks a run active; the card offers "Finish…" mid-run | NOT | `Sharing/ClassroomShareRelease+Vanished.swift` untouched. | Agent F step 2. |
| A stopped run's last deletes aren't confirmed if more batches remain; Finish never nudges an export | CONFLICT | Not fixed. `Sharing/ClassroomShareRelease+Run.swift:206` still replaces the list (`env.setAwaitingGone(Array(originalRecords.values))`), and `+Finish.swift` is untouched. The data-model branch also added `catch { env.setAwaitingGone([]) }` (`+Run.swift:209-212`), which wipes the whole list. | Agent F step 3. "Append instead of replace" must also change that new catch to remove only this batch's records, or a failed later batch erases earlier batches' unconfirmed deletes. |
| The counts disagree (double-count, left children, deleted-elsewhere, mixed-case id) | NOT | `ClassroomLastYearCard.swift` and `ClassroomReleaseSheet.swift` untouched. | Agent F step 4. |
| Local Core Data errors read as "Couldn't hear back from iCloud…" | NOT | `ClassroomShareRelease+RunError.swift` untouched. | Agent F step 5. Keep the plain message for the data-model branch's `RunError.copyVanished` (thrown at `+Run.swift:314`) when adding the Core Data case. |
| A shared mark with no date or a malformed `studentID` fails the backup check every time | NOT | `Backup/BackupRecordCheck.swift` changed only to restrict the fetches to the private store (`BackupRestoreScope.limitToNotebook`, `:84, 91`). | Agent F step 6; start from that version. |
| The closing summary has no timeout | NOT | `ClassroomReleaseModel.swift` untouched. | Agent F step 7. |
| The "export started after the save" time is taken before the save | CONFLICT | Not fixed. `+Run.swift:173, 184` and `:205` set `saved = Date()` before the saving call. The data-model branch put the save inside `deleteOriginals(_:keeping:context:)` (new signature, `:308`) and wrapped it in a do/catch (`:207-212`; the catch is at `:209-212`), so line `:205` is still before the save. | Agent F step 7. Take the stamp after `deleteOriginals` returns, inside the new do/catch, then pass it to `makeSureItExports`. |
| The "only running copy" check isn't repeated during the run | NOT | `ClassroomShareRelease+Live.swift:74-85` untouched. The data-model branch added `CoreDataStack.isSecondaryProcess` (`CoreDataStack+Stores.swift:182`) but the release doesn't use it. | Agent F step 7. `isSecondaryProcess` can be part of `stopReason`, though it is fixed at launch and won't see a copy opened later. |

### History, duplicates and the stack

| Finding | Verdict | Evidence | What's left / which agent |
|---|---|---|---|
| Mid-way through a Replace restore on another device, dedup can keep the outgoing copy and delete the incoming one (tie broken by record name) | NOT | The tie-break is unchanged (`DataCleanupService+Deduplication.swift:65-76`, `+DedupKeepers.swift:58-74`). The data-model branch added `DedupSyncState.noCopySent` (skips only when NO copy has reached iCloud, `Services/Migrations/DedupSyncState.swift:78-84`) and `stillSettling` (attendance only, `:59-74`). | Agent D step 3. Add the "any copy unsent or all just arrived" check to `DedupSyncState` and call it from `foldSameID` (`:132-150`). Don't change `precedesAsCanonical` or the identity-first keepers. |
| Error screen's "Re-download" doesn't clear the flags Reset Local Cache clears | FIXED | Re-download now arms the launch reset (`AppCore/Persistence/DatabaseErrorCoordinator.swift:183-191`), which runs `performLocalCacheReset` → `clearLocalCacheResetFlags` (`CoreDataStack+Stores.swift:275-292`: `checkInLinkRepairHasRun`, `orphanStudentGrace`, history tokens, waiting list, …). One path for both. Test: `DatabaseErrorRecoveryTests`. Commit `4e8f640c`. | Nothing. Drop D step 5. |
| Auto-backup takes its "nothing changed since" mark after writing the file | NOT | `Backup/Core/BackupChangeTracker.swift` and `AutoBackupManager.swift` untouched. | Agent D step 8. |
| With sync off or on the no-iCloud fallback, dedup can't see share zones | FIXED | `DataCleanupService+Deduplication.swift:244-247`: `deduplicateAllModels` returns at once unless `DedupSyncState.mayDeduplicate` (some store has `cloudKitContainerOptions`). That is stronger than D's plan (the whole pass, not just share types). Callers pass the container (`MigrationRunner.swift:94`, `DeduplicationCoordinator.swift:242`). Tests: `DedupSafetyTests`. | Nothing. Drop D step 4. |
| Reset Local Cache request not scoped by environment; no second-copy check | FIXED | `AppCore/Constants/UserDefaultsKeys.swift:211` is now `CloudKitEnvironment.scoped(…)`, and `Settings/DataManagement/DatabaseMaintenanceCard.swift:24` uses it. A second copy: `localCacheResetDecision` returns `.waitForOtherCopy`, and `performLocalCacheReset` needs the exclusive `StoreProcessLock` (`CoreDataStack+Stores.swift:252`). Tests: `StoreProcessLockTests`. | Nothing. Drop D step 6. Re-scoping would double-scope. |
| The no-iCloud single-store fallback makes a history processor that wipes both stores' positions | NOT | `AppCore/Persistence/CoreDataStack.swift:293-295` creates the processor for every stack that opens the app's own stores, including `enableCloudKit: false`. | Agent D step 7: condition it on `opened.isAppNotebook && opened.isCloudKitActive` in `init(opened:)`. |
| Automatic backups made during a first download push out complete ones | NOT | Nothing in `Backup/Core` or `AutoBackupManager` checks `FirstDownloadGate`. The data-model branch gates only restores (`BackupRestoreGate.swift:44`). | Agent D step 8. |

### Names and other shared records

| Finding | Verdict | Evidence | What's left / which agent |
|---|---|---|---|
| The guide is chosen from any classroom's rows when the owner has no name; her own rows are folded across classrooms | PARTLY | Folding fixed: `ClassroomNames.myRows` keeps only rows in the pinned classroom's zone (`Sharing/ClassroomNames.swift:344`, with `zoneName(of:)` at `:369`), and `foldCounting` deletes only copies in the survivor's zone or never sent (`:302`). Test: `ClassroomNamesZoneTests`. | The guide choice is untouched: `snapshot` still does `ownersRow ?? guides.min(by: isNewer)` (`:179-180`). Agent E step 3, bullet 1. Build on `foldCounting`/`zoneName(of:)`, don't redo the scoping. |
| The launch fold can run before that launch's sync and send a stale name over a rename | NOT | `writeWaitingName`'s fold branch (`ClassroomNames.swift:117`) has no import gate. | Agent E step 3, bullet 3. `ImportWatermark.lastImport(into:of:)` (`Services/Sync/ImportWatermark.swift:64-78`) gives "an import since this launch began". |
| A Merge restore puts old names back | NOT | `BackupRestoreRun+LaterTypes.swift` `importV38Entities` (`:289`) is unchanged, and no newer-`modifiedAt`-wins logic exists in `Backup/Import`. | Agent E step 2. |
| Staple history lines keep the name from when they were written | NOT | `Supplies/RestockService+Staples.swift` untouched. | Agent E step 6 (schema 17, `changedByID`). |
| MCP `attendance_for_day` names the front-desk sender by the old stamped name | NOT | `Attendance/Email/AttendanceEmailLog.swift` changed only by `saveSettingsIfMissing`, not at `senderName`. | Agent E step 5. |
| Synced settings don't redraw when iCloud's values first arrive | NOT | `Services/Sync/SyncedPreferencesStore.swift` untouched. | Agent E step 5. |
| On the guide's devices an unnamed assistant reads "another assistant" | NOT | `Attendance/Rules/AttendanceRules.swift` untouched. | Agent E step 5. |

#### Totals (58 findings)

FIXED 11 (#1, #2, #4, #10, #11b, #11d, S6, F1, H2, H4, H5). PARTLY 1 (guide choice and folding). CONFLICT 4 (#7a, #11a, awaitingGone, saved-timestamp). NOT 42, of which 10 are C-owned and already done (#6d, #8a, #8b, seven Assistant bullets).

#### Still to fix, by agent (C excluded)

- **A:** #3, #11a (conflict), #11c, "No students are shared" nil read, pin-save result, pre-pin re-file. Dropped: #1, #4, #11b, #11d, no-iCloud queue (the data-model branch did them).
- **B:** #6a, #6b, #6c, #7a (conflict, re-wire the seam), #7b, overlay after reset, signed-out wording and per-account reset, `.serverResponseLost`/`.zoneNotFound`, `.limitExceeded`, error-key scoping. Dropped: the per-store purge.
- **D:** Replace-restore tie-break, auto-backup baseline token, single-store fallback processor, backups during first download. Dropped: #2, dedup without sync, Re-download flags, Reset Local Cache key and second copy.
- **E:** #5, guide fallback in `snapshot`, launch fold gating, `writeWaitingName` guard, Merge restore and names, staple history names (schema 17), MCP sender name, `SyncedPreferencesStore` redraw, "an assistant" wording, `ClassroomIdentity` account-change refresh. Dropped: #10.
- **F:** #9, two runs at once, awaitingGone and Finish nudge (conflict), the counts, local-error wording, `BackupRecordCheck` date and studentID, closing-summary timeout, saved timestamp (conflict), repeated other-copy check.

#### Notes for rebasing the A, D and E WIP branches

- The data-model branch rewrote A's and D's files. Expect most WIP hunks in `SharedStoreOrphanGuard*`, `SiriHost`, `AppBootstrapping*`, `DataCleanupService+Dedup*`, `WorkModelEntity`, `MigrationRunner`, `CoreDataStack*`, `DatabaseInitializationService`, `DatabaseMaintenanceCard` and `AppBootstrapper` to be obsolete. Start those agents from the data-model files and add only the "still to fix" items.
- Two seams need re-pointing, not just dropping:
  - **B's `beginEarlyEventCapture`:** wire it from `startStoreObservers`, not `getSharedCoreDataStack`.
  - **A's flush timeout:** it must respect `ClassroomShareAttachLock`.
- The data-model branch makes `SiriHost.stack()` async in both apps and changes four Assistant call sites. C's files don't overlap, but compile the Assistant after combining.
- A's step 3, bullet 3 (full filing pass after a restore) and its guard clear contradict the "no sweep" rule; drop them.

</details>

## Phase 2: Combine, schema 17, review, docs, main
- Who: the main session (Opus 5.5, high). One `Plan` agent (Opus) reviews the combined diff for bugs.
- Steps:
  1. **Merge the six branches** (the plan, report and map were committed before Phase 1) into `claude/sync-sharing-bug-hunt-08dddc`, one at a time. Fix the expected `UserDefaultsKeys.swift` overlap. On a conflict elsewhere, the file names say which agents to reconcile. Then wire B's `beginEarlyEventCapture(for:)` into `AppBootstrapping.getSharedCoreDataStack`, right after the stack is made (skipped under unit tests).
  2. **Full builds** through `Scripts/locked_xcodebuild.sh`: `Cosmic Daybook` (iOS Simulator and macOS) and `Daybook Assistant`. Zero warnings, SwiftLint clean on the changed files.
  3. **Whole suites** on the leased simulator through `build-turn`, `-parallel-testing-enabled NO`: the notebook suite (expected around 2,450+, all passing or skipped as before) and the Assistant suite (~235+).
  4. **Review.** A `Plan` agent on Opus reviews `git diff 3fda274e..HEAD` against the report: each finding fixed, nothing that files records by sweep, no `.first`, no `share(_:to:)` on already-shared records, no raw errors on screen. It replies in at most 15 lines. Fix what holds up, then rebuild and rerun the touched suites.
  5. **Schema 17, Development.** A Debug build with `CLOUDKIT_ENVIRONMENT=Development` and the `-InitializeCloudKitSchema` launch argument on the leased iOS simulator, as in `docs/Plans/Plan - Names you set yourself.md` Phase 4 step 6.
  6. **Schema 17, Production.** Open the CloudKit Console in the built-in browser pane. Confirm `CD_changedByID` on `CD_SupplyTransaction` in Development. **Ask Danny in chat before clicking Deploy Schema Changes to Production.** Confirm the field in Production.
  7. **Docs:**
     - The report: each finding gets "Fixed in `<commit>`".
     - `Cosmic Daybook/CLAUDE.md`: schema 16 → 17 and backup v38 → v39 in the Data Model, Sharing Model and Backup lines.
     - `docs/Technical notes/DATA_MODELS.md` and `BACKUP_SYSTEM.md`.
     - `RESTOCK.md`: history shows current names.
     - `CLOUDKIT_GUIDE.md`: Siri files its own marks, Stop Sharing keeps the share on iOS, success only from events.
     - Run `~/.claude/bin/docs-index` on the repo.
  8. **Main.** Squash or merge to main and push, with Danny's OK. If the main checkout is on another branch, land with `update-ref` (memory: merging when the checkout is shared).
  9. **Tide rows** (`Areas/App Development/Cosmic Daybook/TODO.md`, `add_action`):
     - Release: "Roll out the sync and sharing fixes: notebook and Daybook Assistant together; schema 17 is already in Production."
     - Check on a device:
       - A Siri "here" with the notebook closed shows on the Assistant.
       - Stop Sharing on iPad keeps the share, and inviting from the iPad's new members sheet reaches the assistant.
       - The Assistant's status after a Siri mark.
       - Staple history shows a renamed person's new name.
     - Link the rows from the report with their `tide://` links.
  10. Run `~/.claude/bin/sim-lease --done`.
- Cost: ~2–4% of weekly (combine, two schemes on two platforms, two whole suites, one review agent with a fix round, a browser deploy).
- Done when:
  - Both schemes build for iOS and macOS with zero warnings.
  - Both whole suites pass.
  - The review's real findings are fixed.
  - `CD_SupplyTransaction.CD_changedByID` exists in CloudKit Production.
  - Main holds the work and is pushed.
  - `docs-index --check` says the map is current.
  - The Tide rows exist.
- Hand off: no. This is the last phase.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%"). Before Phase 1, commit the report, this plan and `docs/Start here.md` on `claude/sync-sharing-bug-hunt-08dddc`.

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board, if the plan lists one.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in `Areas/App Development/Cosmic Daybook/TODO.md` (or the Daybook Assistant's, for its own), with `add_action`, skipping ones already there. The repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets this plan's status line (`> **Working on it.**` after Phase 1, `> **Done <date>** (<commit>).` after Phase 2, checked against main) and runs `docs-index`.
7. Both phases run in this session, so there's no starter prompt between them. If the session has to stop between phases, the starter prompt is: "Model: Opus 5.5, effort: high" then "In /Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/bug-hunt-report-ad32c2, read docs/Plans/Plan - Sync and sharing fixes.md and do Phase 2. Follow its Starting a phase and Ending a phase steps." The six agent branches are named `worktree-agent-*`; `git branch --list 'worktree-agent-*'` with their commit messages identifies them.

## Open questions
None.
