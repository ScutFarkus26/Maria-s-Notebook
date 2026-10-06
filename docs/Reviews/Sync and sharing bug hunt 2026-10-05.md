# Sync and Sharing Bug Hunt (2026-10-05)

Base: `3fda274e` (main). Read only: six reviewers each took one part (share setup and filing, Remove Last Year, sync status, history and duplicate cleanup, the Daybook Assistant's sync, names and the other shared records), then the worst findings were checked against the code by hand. Nothing was changed, built or run.

The same day's data-model bug hunt (another session, also at `3fda274e`) found three of these too: #1 (Siri marks), #4 (the 2,000 cap) and the work-item check-in sweep in #2. Fix each once.

**Sure** means the path was traced in the code end to end. **Likely** means the code path is real but the outcome depends on how iCloud or iOS behaves, or on timing.

## Where the findings stand (2026-10-06)

The fixes follow [Plan - Sync and sharing fixes](<../Plans/Plan - Sync and sharing fixes.md>); its Phase 1b table has the verdict for every finding, with evidence.

- **Fixed by the data-model plan** (main `0ab967ff`):
  - #1 Siri marks
  - #2 duplicate cleanup keeps children, and the work check-ins
  - #4 the 2,000 cap
  - #10 the front-desk email settings
  - #11b and #11d
  - per-store history purge
  - the no-iCloud queue
  - the error screen's Re-download flags
  - dedup without sync
  - Reset Local Cache scoping and the second-copy check
- **Fixed on main 2026-10-06** (one squash, with schema 17 deployed to CloudKit Production; branch commits named for the record):
  - Daybook Assistant sync (`2f163a80`): #6's fourth bullet, #8, every smaller Daybook Assistant finding.
  - Share setup (`a5888b34`): #3, #11a, #11c, the "no students" nil read, the pin save, the pre-pin re-file.
  - Names and schema 17 (`29d16f32`): #5, the names findings, the account-change ID, staple history names.
- **Fixed on main 2026-10-06, second squash** (Danny chose to finish before the reset):
  - Sync status: #6's first three bullets, #7, and the smaller monitoring list.
  - The remaining stack items: the Replace-restore tie-break, the auto-backup token, the single-store processor, backups during a first download.
  - Remove Last Year: #9 and its smaller list.
  - Five more from an Opus review of that work:
    - Sync Now claimed success.
    - Events posted before the stores opened went unheard.
    - A setup left the spinner on.
    - An account change kept the old account's dates.
    - The backup wait had no time limit.

  **Every finding in this report is now fixed.**

## Verdict

The core holds up. The pieces that move records between places are careful and found sound:
- The one pinned share, and never using `.first`.
- Filing only records that are in no share.
- Remove Last Year's copy, confirm on iCloud, then delete.
- History kept per store, and the first-download gate.
- Keeping the stand-in owner ID out of attribution.

The problems are at the edges:
- **Ways in that skip the filing step.** Siri with the app closed, a restore, a stuck attach.
- **The duplicate cleanup.** It deletes an extra copy's contents along with it.
- **The sync status.** It says "synced" too easily and "damaged" too long.
- **Recovery paths.** Stop Sharing on iPhone and iPad, and the error screen's Re-download.

## Fix first

### 1. A Siri mark made while the notebook is closed never reaches the Assistant (Sure)
The guide says "Mark Maya here" on a locked iPhone where iOS has closed the notebook. The mark is saved in her own notebook, but nothing files it into the classroom share. The filing step (`SharedStoreOrphanGuard`) only starts with the main window, and a Siri launch in the background opens no window. `SiriHost.didSave` is empty because it counts on the filing step. Nothing sweeps later, so Maya shows unmarked on the assistant's phone, and she may mark her again.
- Where: `Cosmic Daybook/Siri/SiriHost.swift:78-80`, `Cosmic Daybook/AppCore/AppBootstrapper.swift:92`, `CosmicDaybookApp.swift:113-115`
- Fix: in `SiriHost.didSave`, start the guard (it's safe to call twice), queue the new records and file them, as the Assistant's `AssistantSiriHost.didSave` already does.

### 2. Duplicate cleanup throws away what hung off the extra copy (Sure, rare trigger)
When sync leaves two copies of one record (same `id`), the cleanup deletes one. For four kinds it deletes without moving anything across first, so Core Data's cascade deletes what belonged to that copy, and the delete syncs everywhere:
- tracks (steps and enrollments)
- lessons (attachments and sample works)
- todos (subtasks)
- community topics (solutions and attachments)

Separately, deleting a duplicate work item sweeps away check-ins that carry only its `workID` text. Those check-ins belong to the surviving copy too.
- Where: `Services/Migrations/DataCleanupService+Deduplication.swift:321, 360, 372`; `+DeduplicateLessons.swift:89-121`; `Work/Models/WorkModelEntity.swift:44-52` with `+DeduplicateWork.swift`
- Fix: give each a merge that moves the children onto the survivor first (`merge(duplicateTrack:)` and `merge(duplicate:into:)` already do this for the same-title merges), and relink text-only check-ins before deleting a work duplicate.

### 3. "Stop sharing…" on iPhone or iPad deletes the classroom share, and setup can't be redone (Likely)
On the Mac, Stop Sharing removes everyone but keeps the share, on purpose, because a new share would be a second zone. On iPhone and iPad the button opens Apple's sharing sheet, whose Stop Sharing deletes the share itself. The pin still names the old zone, so Set Up Classroom Sharing then refuses with "still coming down from iCloud" every time (that branch is sure). New classroom records wait forever.
- Where: `Settings/Classroom/ClassroomSharingView.swift:239-245`, `ClassroomSharingViewParts.swift:198-203`, `Sharing/ClassroomSharingService+Setup.swift:119-120`
- Fix: on iOS, route Stop Sharing to `removeAllMembers()` as the Mac does, and keep the system sheet for inviting only.

### 4. A restore can overflow the share's waiting list and drop the very records it restored (Sure)
The filing step's waiting list holds 2,000 records and trims the oldest. A save lists new records first, then each updated student with all of her attendance from this year.
- **Replace restore:** with more than 2,000 classroom records, it loses whatever was trimmed.
- **Merge restore:** setting every field on existing students likely counts them all as updated, which queues thousands of already-shared marks behind the restored records. The trim then removes the restored ones.

Either way, those records stay out of the share until the guide sees the Settings count and presses Add Them to the Share.
- Where: `Sharing/SharedStoreOrphanGuard.swift:62-63, 100-120, 142-152`; `Backup/Import/BackupEntityImporter+Students.swift:17-41`
- Fix: only queue a student whose enrollment fields really changed, trim from the end, and after a restore run setup's full filing pass instead of the list.

### 5. A Merge restore can re-share a staple that's already shared (Likely)
Restoring a missing supply-history line links it to its staple through the `supply` relationship. Filing that line into the share then carries the already-shared staple along with it. `RestockService.historyEntry` avoids that relationship for this reason: "a staple already in the classroom share must never be shared again". On 2026-09-27 re-sharing records stopped sync for the session.
- Where: `Backup/BackupRestoreRun+LaterTypes.swift:256-260` (parent link from `Backup/ModelRowKinds.swift:197-201`)
- Fix: restore supply history by `supplyID` only, without setting `supply`.

### 6. The sync status says "synced" when nothing went (Sure)
Four separate ways:
- **Your own saves count as news from iCloud.** A save on this device posts a "remote change" too; the code itself notes this at `AssistantBootstrapper.swift:326`. Half a second later it is logged "Got changes from iCloud" and the app stamps "Last synced: now". It also clears the shown error, zeroes the waiting count (which is one of Remove Last Year's checks), and cancels the save's 10-second "You're offline" check and any retry. (`CloudKitSyncStatusService+EventHandlers.swift:129-153`)
- **The automatic retry pretends.** After a failed send, the retry calls Sync Now, which saves an empty context. It clears the error, stamps "Last synced: just now" and logs "You tapped Sync Now", though nobody did. Its task is never cleared, so it keeps saying "Trying again soon". (`CloudKitSyncStatusService.swift:282-301, 356-389`; `SyncRetryLogic.swift`)
- **The toolbar dot ignores per-store health.** If the classroom share is refused while the notebook itself syncs, Settings says the share is stopped but the dot reads fine. The 10-01 fix reached Settings and `sync_status`, not the dot. (`Components/Shared/SyncStatusIndicator.swift:16-23`)
- **The Assistant's "All marks sent" misses Siri marks.** The last-save time is only written by the status line's own save listener. A Siri mark made with the app closed and sent while offline later shows as sent. (`Daybook Assistant/Sync/AssistantSyncStatusView.swift:96-105`)
- Fix: count only a successful import or export as synced; retries shouldn't stamp success or log a tap; drive the dot from `syncHealth`; record the Assistant's last shared save for the whole app (beside `UnsentChangesKeepAlive`), not in the view.

### 7. A sync problem at launch goes unseen, and a recovered one keeps saying "damaged, re-download" (Sure path, Likely trigger)
- **The blind start.** Nothing listens for iCloud's events until the bootstrap has finished plus 2 seconds. A setup failure at launch (a schema refusal, no account) lands in that gap, so the app reports "iCloud sync is on" and healthy. (`CloudKitSyncStatusService.swift:242-256`)
- **The flag that never clears.** Any setup failure sets the "sync stopped" flag, and nothing ever clears it. After a passing failure (signed out, then back in) that is fixed in the same session, the banner says your copy is damaged and suggests Re-download from iCloud, which throws away unsent changes. Until relaunch it also stops new classroom records being filed and blocks setup and Remove Last Year. (`+EventHandlers.swift:413-425`, `SyncStoppedAdvice.swift:46-58`)
- Fix: create the event stream as soon as the stack exists, and clear the flag when the store that set it next succeeds.

### 8. Leaving a class on the Assistant can throw away a mark that hasn't gone (Sure logic, narrow timing)
"Has everything gone?" remembers only the first unsent save. Say she marks A, an upload starts, she marks B, and the upload finishes. It counts as covering both, though B wasn't in it. Leave → Wait then says her marks reached the guide and removes the class, B included.

Separately, Leave keeps the Assistant's list of records still waiting to be filed. If she later joins another class, those old records are filed into the new class.
- Where: `Services/Sync/UnsentChangesKeepAlive.swift:102-110` (pinned by `UnsentChangesKeepAliveTests.firstSaveCounts`); `Daybook Assistant/Sync/AssistantBootstrapper+Class.swift:122-139`; `AssistantClassroomLocalState.forget` doesn't clear `Assistant.pendingShareAttach`
- Fix: track the newest save, not the first; on Leave, wait for the running pass, delete the waiting records and clear the list before removing the class.

### 9. Remove Last Year re-plans with a start date the guide never saw (Sure, rare trigger)
`start()` makes the backup, then plans again with today's school-year start, but it never checks that this is still the date the preview showed. It also doesn't re-run the "attendance just before the start" guard. A start changed while the sheet is open (synced from another device, or by the MCP calendar tool) moves this year's first weeks out of the share. Nothing leaves the notebook; Add Them to the Share puts them back.
- Where: `Settings/Classroom/ClassroomReleaseModel.swift:74-97`
- Fix: refuse when the fresh plan's start differs from the preview's, and re-run the guard on it.

### 10. Opening the notebook can put old front-desk email settings over new ones (Likely)
The guide's devices copy their own email settings into the shared settings row at every launch, and whenever the settings screen opens, stamping it as the newest. Say the Mac changed the recipients, and the iPad's iCloud key-value copy hasn't caught up when it launches. The iPad then writes its old recipients over the Mac's, and the assistant's email goes to the old people. A device whose key-value storage hasn't synced yet can write no recipients at all.
- Where: `AppCore/AppBootstrapper.swift:164`, `Attendance/Email/AttendanceEmail+Prefs.swift:64-69`, `AttendanceEmailLog.swift:217-246`
- Fix: write the row only on an explicit edit, as `SchoolYearSync` does.

### 11. The notebook's filing step can stall or collide (Likely)
- **One stuck attach stops filing until relaunch.** An attach call that never returns leaves `flushTask` set, so nothing new reaches the share until the app restarts, which on an iPad can be days. (`SharedStoreOrphanGuard.swift:172-187`)
- **Setup and the filing step can attach the same records at once.** This can loop on a stale copy of the share, which is how the 2026-09-28 setup hung. (`ClassroomSharingService+Setup.swift:45, 64, 83`)
- **The Mac's members sheet saves the store's possibly old copy of the share.** That is the stale-copy problem 0f312b91 fixed for attaching. (`ClassroomSharingService+Members.swift:53, 116`)
- **Each new mark costs a share read on the main thread.** This can hitch the guide's iPad or Mac as she takes attendance. (`SharedStoreOrphanGuard.swift:203`)
- Fix: put a timeout on each attach, hold the guard while setup runs, fetch the latest share before member changes, and use the async share read.

## Smaller findings

**Sync status and monitoring**
- After Reset Local Cache the "Syncing from iCloud…" overlay never shows, because the old last-sync date survives. (`CloudKitSyncStatusService.swift:175-186`)
- Signing out of iCloud still reads "iCloud sync is on". Switching Apple Accounts while the app runs keeps the old account's record ID (the "you" and name rows) and sync dates, in both apps. (`CloudKitHealthCheck.swift:178-237`; `ClassroomIdentity.swift:52-62`)
- `.serverResponseLost` and `.zoneNotFound` read as "stopped" rather than temporary, and block Remove Last Year until a success. (`CloudKitStoreHealth.swift:230-235`)
- `.limitExceeded` shows as "iCloud storage is full". (`CloudKitConfigurationService.swift:164-167`)
- The saved last-error keys aren't scoped by environment. (`UserDefaultsKeys.swift:27-32`)
- One export date guards history purging for both stores; the 180-day floor is all that protects a stuck store. Keep a date per store, as `AssistantHistoryTrim` does. (`+EventHandlers.swift:298-309`, `PersistentHistoryProcessor.swift:243-264`)

**Daybook Assistant**
- The status line sticks on "Sending to iCloud…" after a visit to Restock: the upload listener is a view `.task`. (`AssistantSyncStatusView.swift:106-107`)
- A record written by another screen's save (after the grid's own save failed) is never handed to the filing list. (`AssistantSave.swift:19-25`)
- A "sync stopped" report that arrives while starting, failing or leaving is dropped, and marks stall silently until relaunch. (`AssistantShareAttacher.swift:228-238`)
- Her name row:
  - It is written at launch even when she isn't in a class, then retried every 10 minutes.
  - It isn't rewritten after Leave and re-join.
  - A name set in the Sample Class or offline only arrives at the next cold launch.
  - (`ClassroomNames.swift:99-112`, `AssistantNameStore.swift:36-82`)
- Leave warns about unsent marks right after joining, because a private-store-only save counts as unsent. (`UnsentChangesKeepAlive.swift:59-85`)
- A stack rebuild sleeps 300 ms instead of waiting for a running attach. A pass that finds no shared store mid-rebuild drops its list. (`AssistantBootstrapper.swift:144-157`; `CDAttendanceStore+ClassroomShare.swift:53`)
- With two zones in her shared store, a new mark can land in the wrong one and still count as filed. (`ClassroomShareAttach.swift:106-113`)

**Share setup and filing**
- Records made during a launch that fell back to "no iCloud" are never queued. (`SharedStoreOrphanGuard.swift:125`)
- Manage Sharing says "No students are shared yet" when iCloud simply didn't answer. (`ClassroomSharingService+Setup.swift:158-162`)
- Setup ignores whether saving the pin worked. (`+Setup.swift:146`)
- After setup on the Mac, the iPad can re-file records it queued before the pin arrived, from a half-downloaded view. (`SharedStoreOrphanGuard.swift:124-131`)

**Remove Last Year**
- Two runs at once would delete the only private copy. Nothing marks a run as active, and the card offers "Finish…" mid-run. There's no way to open a second sheet in the shipping Mac app; the iPad rehearsal flag has one. (`ClassroomShareRelease+Vanished.swift:49-77`)
- A stopped run's last deletes aren't confirmed if more batches remain, and Finish never nudges an export. (`+Run.swift:203`, `+Finish.swift:17-19`)
- The counts disagree:
  - The card double-counts half-moved records.
  - "Marks for children still in class" includes children who left.
  - The report counts records deleted elsewhere as moved.
  - A mixed-case `studentID` leaves a count with no button.
  - (`ClassroomLastYearCard.swift:13`, `ClassroomReleaseSheet.swift:91-94`)
- Local Core Data errors read as "Couldn't hear back from iCloud… check you're online". (`+RunError.swift:61-71`)
- A shared mark with no date or a malformed `studentID` fails the backup check every time. (`BackupRecordCheck.swift:59-75`)
- The closing summary has no timeout, so the sheet can hang with no way out. (`ClassroomReleaseModel.swift:118`)
- The "export started after the save" time is taken before the save. (`+Run.swift:173-175`)
- The "only running copy" check isn't repeated during the run. (`+Live.swift:74-85`)

**History, duplicates and the stack**
- Mid-way through a Replace restore on another device, the duplicate cleanup can keep the outgoing copy and delete the incoming one for private-only types (a tie broken by record name). (`DataCleanupService+Deduplication.swift:63-89`)
- The error screen's "Re-download from iCloud…" doesn't clear the flags that Settings' Reset Local Cache clears: the check-in repair flag and the orphan grace. (`DatabaseInitializationService.swift:27-35` vs `CoreDataStack+Stores.swift:179-191`)
- Automatic backup takes its "nothing changed since" mark after writing the file, so a change made during the write (an assistant's marks arriving) is never backed up until something else changes. (`BackupChangeTracker.swift:58-63`, `AutoBackupManager.swift:396-404`)
- With sync off, or on the no-iCloud fallback, the duplicate cleanup can't see share zones. So it doesn't protect both copies of a half-moved record, and its winner differs per device. (`DedupShareBoundary.swift:24-37`)
- The Reset Local Cache request isn't scoped by environment: a Development launch next wipes the frozen Development notebook. It also doesn't check for a second running copy. (`UserDefaultsKeys.swift:209`)
- The no-iCloud single-store fallback makes a history processor that wipes both stores' history positions. The cost is a big re-read next launch; nothing is lost. (`CoreDataStack.swift:231-233`)
- Automatic backups made during a first download count toward the 10 kept, and can push out complete ones.

**Names and other shared records**
- The guide is chosen from any classroom's rows when the owner has no name yet. Her own rows are folded across classrooms. (`ClassroomNames.swift:175-178, 284-322`)
- The launch fold can run before that launch's sync and send a stale name over a newer rename. (`ClassroomNames.swift:113-115`)
- A Merge restore puts old names back, and nothing rewrites the current ones. (`BackupRestoreRun+LaterTypes.swift:288-297`)
- Staple history lines keep the name from when they were written, which falls short of the plan's "on old entries too". (`RestockService+Staples.swift:191-195`)
- The MCP `attendance_for_day` names the front-desk sender by the old stamped name. (`AttendanceEmailLog.swift:191-195`)
- Synced settings don't redraw when iCloud's values first arrive on a new device. (`SyncedPreferencesStore.swift:158-194`)
- On the guide's devices, an unnamed assistant reads "another assistant", not "an assistant". (`AttendanceRules.swift:74-75`)

## Checked and holds up

- **Choosing the share:** only the pinned share, never `.first`.
- **Setup:** it is the only thing that makes a share, and it refuses a second zone.
- **Filing:** every attach filters to records in no share, with the latest share copy each time.
- **New types:** Supply, SupplyTransaction, OrderItem and ClassroomPerson are handled wherever the older types are (scope, setup, counts, permissions, filing).
- **Remove Last Year:**
  - Copies carry every attribute (`leavesAt`, `returnedAt`, `statusBeforeLeavingRaw`, `note`, `recordedByName`).
  - Twins match case-insensitively.
  - Copies are confirmed on iCloud before any delete, and deletes are confirmed after.
  - A departed child and her marks move in one save.
  - Its copies are never filed back.
- **`DedupShareBoundary` and `OrphanStudentGrace`:** both are wired into both dedup passes and both orphan cleanups.
- **First-download gate:** opens only on a successful private-store import. History positions are kept per store, with purge rules as documented. No processor runs for Sample Class or the Assistant.
- **The Assistant's filing queue:** one pass at a time, the list scoped by environment, retries with rest, the invitation inbox, Leave's share choice, and the iOS 18 floor.
- **Stand-in owner ID:** `__defaultOwner__` is cleaned wherever IDs are stamped or compared. The name row goes to the right store in both apps. Backup v38 carries ClassroomPerson. `SchoolYearSync` only publishes on explicit edits.

## Doc drift

`CLOUDKIT_GUIDE.md` §2 still says the release checks the backup with `BackupReader.verifyStructure`; it now uses `BackupRecordCheck`, record by record.
