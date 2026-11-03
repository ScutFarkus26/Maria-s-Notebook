# Sync, sharing, Core Data, migrations and backups bug hunt 2026-11-02

> **All fixed 2026-11-03** (main `4180d0aa`). Found at main `8803b6da`.
> In short: nine read-only reviewers each took one area (the Core Data stack, sync status and history, share setup and filing, Remove Last Year and the names, backup writing, backup restore, migrations and cleanups, the Daybook Assistant's sync, the Tide to-dos); 59 findings, the top ones in each area checked by hand against the code. The hunt itself changed nothing; seven fix agents and a cold review then fixed all 59 (see "Where the findings stand"), and what is left is checking on the devices.

Paths are under `Cosmic Daybook/` unless they start with `Daybook Assistant/`.

**Sure** means the path was traced in the code end to end. **Likely** means the code path is real but the outcome depends on how iCloud, iOS or timing behaves. Findings 1–12, 25, 29, 36, 42, 43, 52, 53 and 57 were checked by hand after the reviewers reported them; the rest are each reviewer's own trace.

## Where the findings stand

Fixed 2026-11-03 by the plan [Plan - Sync, sharing and backup fixes 2026-11](<../Plans/Plan - Sync, sharing and backup fixes 2026-11.md>): seven fix agents (A to G) each owned a set of files, then a cold review of the combined work found three more problems and nine leftovers, fixed in one more commit. Every finding below is fixed; the "Fix:" lines in this report are what was suggested, and these lines say where the fix went another way. Nothing here has been checked on a device yet (see "What next").

- **A, Restore (#1, #2, #7's importer, #10, #22, #23):** a Merge keeps a stored record with a later change date, and the preview counts those as kept. About 40 kinds of record have no change date (lessons, work, presentations, meetings, to-dos and the like) and still take the backup's version, except that a to-do ticked since the backup stays done and a note edited since is kept (the cold review's fix); `ClassroomPerson` keeps its 2026-10-29 rule. A Replace updates the 15 classroom-share kinds in place and deletes only what the backup lacks, so the class keeps its place in iCloud. Beyond the report's fix, a Replace also leaves a kind alone when its backup entry couldn't be read or the backup is too old to hold it, and refuses to start when a kind every backup holds can't be read. The Merge preview now counts every kind. Also fixed here: a crash since 2026-10-06 when a restore on two stores updated a saved record.
- **B, Backup writing (#9, #12, #13, #14, #15, #16, #17, #18, #19, #20, #21):** as the report suggested, with these differences. The four automatic-backup switches stay each device's own and the report's "start the schedule again" step was dropped, since nothing restores an interval any more (#19). Dates are written to the millisecond, not the full fraction, and older whole-second archives still read (#20). The backup key is not one shared item: each key is its own Keychain item stamped with when it was made, every key is kept for reading, every device writes with the oldest, and none is made during a first download (#15). A backup made during a first download is written as a `Partial-` file that trimming and "newest backup" skip (#14).
- **C, Stack, sync status and launch repairs (#4, #7's repair, #24, #25, #26, #27, #28, #52, #54, #55, #56, #57, #58, #59):** #52 sets aside only a shared store with no rows at all; one that holds rows is no longer moved without a word. #54 waits out another copy's migration for 10 minutes (the report said wait with no limit). #55 trims set-aside notebooks after 30 days, and never while iCloud sync is off (added by the cold review). The first-download lift asks twice and is taken back when an account signs in (#26).
- **D, Share setup and members (#8, #29's picker, #30, #31, #32, #35, #40, #41's refreshContents):** classroom-sharing setup and "Add them to the share" run on the Mac only, which is how #30 is closed beyond asking the server again just before the share is made; the iPad and iPhone say it is set up on the Mac. The Add Member picker no longer offers View only (#29).
- **E, Daybook Assistant (#5, #6, #29's read-only line, #33, #42, #43, #44, #45, #53's Leave context):** #29 reads the participant's permission from the share and from `canModifyManagedObjects(in:)`, since the SDK says the latter answers at the database level; marking turns off and a plain line says so. #42 keeps the screens up through the rebuild's waits, but they still come down for the 0.3 second swap. #43 counts attendance marks as marks, her name not at all, and Restock and sends as other changes.
- **F, Tide (#3, #11, #46, #47, #48, #49, #50, #51):** the edit decision (#3) carries a new title or due date to Tide for a to-do made in Tide; a past due date stays here and is said once. A tick and a delete arriving together from another device can't be recovered without a model change, and edits held back are remembered for the session only.
- **G, Remove Last Year (#36, #37, #38, #39, #41, #53's release context):** #36 adds a "blocked" stage with its own plain line, so the sheet shows only what stops the run and has Cancel while it reads. The run's context comes from `newBackgroundContext()` but goes back to the strict error merge policy, so a change made meanwhile sends the batch back instead of being overwritten.
- **Cold review (3 problems, 9 leftovers, commit `34a14eef`):** a Merge also keeps notes edited since the backup and to-dos ticked since, and Settings names the kinds it can't judge. Set-aside notebooks are never deleted while sync is off. The restore's iCloud wait counts only an export started after its own save began. The sync status's event listener now listens as it starts, so no early event is missed. The dashboard's Back Up Now warns about a half-downloaded notebook. The iPad Restock banner points to the Mac. Restock, in the tab and through Siri, changes nothing while the share is View only. Test fixes, and one stale test now expects what the plan decided (a pad she changed after the backup stays as she left it).
- **#34 (the Sharing Model text):** `Cosmic Daybook/CLAUDE.md` now says 15 types and schema 22.

## Scope

The earlier hunts went line by line through recent diffs (10-29 read every line changed since 09-30 in these areas). This one went by topic over the whole of each area, whenever its lines were last changed: `AppCore/Persistence`, `Services/Sync`, `Sharing`, `Settings/Classroom`, `Settings/Sync`, `Backup`, `Services/Migrations`, `Services/Tide`, `Daybook Assistant/Sync`, and the Core Data model's schemas 19–22. The 2026-10-05 sync and sharing hunt's fixes were re-read for regressions; none was found.

## Verdict

The moving parts that cost most are sound: the one pinned share, filing only unshared records, Remove Last Year's copy-confirm-delete, per-store history, the first-download gate, the dedup survivor rules, the schema guard, and the backup archive's write-verify-rename. Schemas 19–22 are all additive and lightweight-safe.

The problems are where two features meet:
- **Restore meets sync and sharing.** Merge silently rewinds every record the backup holds; Replace on the sharing Mac deletes the whole class from iCloud and re-shares it minutes later; project sessions come back unlinked.
- **Tide meets the rest of the notebook.** A to-do made in Tide can't be edited here; a tick is lost if the to-do is cleared before the Mac has told Tide.
- **Error paths that never clear.** The notebook's sync-retry toast storm; the Assistant's dead delegate found on an ordinary export; "Not in This Class" lingering after a new join, with a Leave button that purges the new class.
- **What the guide is told.** Backup failures and the skipped files are never shown; the Remove Last Year sheet has no way out while it reads.

## Fix first

### 1. Merge restore quietly rewinds every record the backup also holds, and Settings says the opposite (Sure)
Merge is an upsert where the backup wins for any `id` it carries (by design since 2026-09-05); nothing compares `modifiedAt`. The only newer-wins checks are the names people set and lesson files' change dates. The Settings line says "**Merge:** Add what's in the backup and keep everything else," and the preview's chip says "already here N," which reads as "left alone."
- Scenario: the guide wants back one lesson she deleted, picks Merge with last week's backup. Every attendance mark, note edit, presentation, enrollment change and to-do tick of the past week that the backup also holds goes back a week, with `modifiedAt` set to the old value; the reverted marks sync to the Assistant's phone as the newest change. To-dos ticked since come back open, and the Tide sync finds their Tide action already done and leaves them open here for good.
- Where: `Backup/Import/BackupEntityImporter.swift:21-29` (the design note), `+Students.swift:17-47`, `+Calendar.swift:50-67`, `+Lessons.swift:21-59`; `Settings/DataManagement/DataManagementPanel+RestoreCard.swift:28-31`; `Backup/RestorePreviewView.swift:98-101`.
- Fix: in Merge, skip a row whose stored record has a newer `modifiedAt` (generalize `rowsOlderThanStored` from `BackupRestoreRun+LaterTypes.swift:312-325` into the importers; nil on either side means take the backup), count those as kept in the preview, and reword the Settings line. If backup-wins is what Danny wants, the line and the chip must say every record the backup holds goes back to the backup's version.

### 2. Replace on the sharing Mac deletes the whole classroom from iCloud, then re-shares it minutes later (Sure for the churn; Likely for losing the share)
`deleteAll` clears every record in the private store, and on the lead guide's Mac that store holds the classroom share's zone. The restored students, marks, days off, staples and needs are new objects in the private default zone, saved in the same save as the deletes. One export tells iCloud: delete every shared record; add unshared copies. Replace isn't refused with sync on.
- Scenario: the Assistant's phone empties. The copies reach the share only when the orphan guard runs a later pass (sync on, no first download, pin found, not waiting for an import after a pin, attach lock free), then export again and import on her phone. Marks the assistant made since the backup are deleted from iCloud, which "match the backup" implies, but a new share record identity for every child is not. Only `ClassroomPerson` rows survive in the zone, and those exist only once someone typed a name; if no one has, the save leaves the zone with nothing but the CKShare. Whether NSPersistentCloudKitContainer drops a share whose zone has no objects left needs checking against Apple's documentation; if it does, the pin names a gone zone and setup refuses for good (the failure `Sharing/ClassroomSharingService+Members.swift:11-14` describes).
- Where: `Backup/BackupService+Helpers.swift:49-91, 97-108`; `Backup/BackupFetchHelper.swift:214-223`; `Backup/BackupService+Restoration.swift:200-203`; `Sharing/SharedStoreOrphanGuard.swift:84-92, 180-209`.
- Fix: in Replace, treat the 15 share types the way `mergedOnReplaceEntityNames` treats names: update records by `id` in place and delete only the ids the backup lacks, so shared records keep their CloudKit identity and zone and the Assistant sees edits rather than a wipe.

### 3. A to-do that came from Tide can't be edited here: the edit is undone, and the editor says the opposite (Sure)
`judge` calls `followTide` for every `fromTide` to-do that is open and still in Tide, which writes Tide's title and due date back over the notebook's. The editor's line reads "Tide keeps this to-do's wording, so a new title here stays in the notebook."
- Scenario: a to-do made in Tide shows in the notebook. The guide opens it on the iPad or Mac, fixes the title or sets a due date, saves. Thirty seconds later the Mac's run writes Tide's title and due back (`due` becomes nil again), and the iPad gets the revert through iCloud. Every later edit is undone the same way.
- Where: `Services/Tide/TideSyncEngine+Steps.swift:71` (the `fromTide` branch), `:92-96` (`followTide`); `Services/Tide/TideTodoStore.swift:134-140`; `Todos/Views/EditTodoForm.swift:23-24`; `Services/Tide/TideSyncMessages.swift:60-63`.
- Fix: either carry the notebook edit to Tide for a `fromTide` to-do (`update_action` with the new words and `due`, the way a Tide reword is carried here), or make title and due read-only for Tide-made to-dos and say "Change it in Tide." `CDTodoItem` has no `modifiedAt`, so "who changed last" can't be decided; one owner per direction is the honest fix.

### 4. After five failed syncs, every further failure pops a five-second "Couldn't sync with iCloud" toast (Sure)
Every failed import or export event calls `scheduleRetry()`, which bumps `retryAttempt` once per event, not per retry of one failure: the retry task runs `retrySync()`, which returns true when the view context has nothing to save, so it never reschedules; the counter is only reset by a successful import or export, by Sync Now's clear, or by the network coming back. On the sixth failed event the guard calls `onMaxRetriesReached`, and does so again on every failed event after that. That lands in `reportRetriesExhausted`: a persisted "keeps failing" error, a history row, and a 5-second error toast with Retry. `ToastService` has no dedup; it queues.
- Scenario: the classroom share's export is refused or its delegate is dead (the 2026-09-30 shape). A guide taking attendance for 25 children gets about two minutes of stacked toasts; Retry runs `syncNow()`, which saves nothing useful and doesn't reset the counter.
- Where: `Services/Sync/CloudKitSyncStatusService+EventHandlers.swift:396-398`; `Services/Sync/SyncRetryLogic.swift:53-56`; `+Retry.swift:54-56`; `+ShownError.swift:127-145`; `Components/Toast/ToastService.swift:134-139`.
- Fix: count attempts per failure chain (bump only when a retry actually ran and failed), show the exhausted toast at most once per chain (a flag cleared on the next success), and don't call `onMaxRetriesReached` from the guard on every event.

### 5. Assistant: a dead delegate found on an ordinary export holds all sending for the rest of the session, and nothing rebuilds or says so (Likely)
`AssistantFilingHold.follow` holds the store for `killedDelegate` and only fires `onSetupFailedForAccount` for the account case. The hold lifts only on a later successful import or export, which a dead delegate never produces. Every pass returns at `filingWaits()` before any attempt, so `mirroringStopped(on:)` (reached only from a round's result) is never reached, `onStalled` never fires, and the bootstrapper's one-time rebuild for a stop never runs. The sync line has no "held" state: it reads "Sending to iCloud…" for good.
- Scenario: on a plain Core Data export the shared store hits 134421, 134406 or NSFileReadUnknownError. Every mark that morning sits on the phone until she happens to quit. Leave › Wait says "Check that this iPhone is online" though she is (finding 45).
- Where: `Daybook Assistant/Sync/AssistantFilingHold.swift:80-94`; `AssistantShareAttacher.swift:287` with `+Hold.swift:55-59`; `+Rounds.swift:38, 62-72, 99-111`; `AssistantBootstrapper+Class.swift:133-156`; `AssistantSyncStatusView.swift:113-125`.
- Fix: give `AssistantFilingHold` an `onMirroringDied(container)` callback beside `onSetupFailedForAccount`, routed by `followFailedSetup` (`+Rebuild.swift:102-108`) into `mirroringStopped(in:)`; and let the sync line read `AssistantStack.filingStopReason`, so a held send shows as "Not sent yet… trying again" (or "quit and reopen" once the stop gave up). The same wording gap applies to a first launch offline: setup failed for the network, marks wait under the hold, the line says "Sending to iCloud…".

### 6. Assistant: "Not in This Class" lingers after she joins a new class, and its Leave button purges the new class (Sure path, timing-dependent)
After the guide re-shares, her phone shows "Not in This Class" (`removedFromClass`). Opening the new invitation pins the new zone and posts `.didJoinClassroom`, whose handler calls `refreshMembership`; with a row already there and the phase already `.ready`, it returns before `checkStillInClass()`, so `removedFromClass` stays true until the first shared-store remote change arrives. Meanwhile the removed-from-class view stays up with its Leave button. Tapping it: `leaveClassroom` sees `removedFromClass`, clears the share state, and the service's `leaveClassroom` resolves `pinned` from the now-updated pin, finds the new class's share, purges it and deletes the rows. She is back on the join screen and must open the invitation again.
- Where: `Daybook Assistant/Sync/AssistantBootstrapper.swift:315-340` (the early return at `:328`); `+Observers.swift:60-62, 110-123`; `AssistantAttendanceView.swift:274`; `+Leave.swift:36`; `Sharing/ClassroomSharingService.swift:261-273`; `Sharing/ClassroomLeave.swift:23-30`.
- Fix: in the `.didJoinClassroom` handler set `removedFromClass = false` and call `checkStillInClass()` unconditionally; and in `leaveClassroom`, when `removedFromClass`, purge nothing (pass an explicit "no share" rather than letting `shareToLeave` fall back to whatever the pin now names).

### 7. Restored project sessions aren't linked to their project (Sure)
`importProjectSessions` sets the `projectID` string only; no parent lookup is passed although projects are imported first and `index.related(CDProject.self, id:)` would find them. Nothing relinks later. The app links sessions through the relationship and reads them through it: the project page, last activity and the school-year lens, the session page's roster, check-in saves, and the MCP project tools. Only `ProjectDeletion` tolerates the string. The relationship is optional, so the save succeeds silently.
- Scenario: after a Replace (or a Merge that brings sessions this device lacks), every book club and project shows no sessions, a project with only restored sessions looks inactive, and a restored session's page shows no members.
- Where: `Backup/Import/BackupEntityImporter+Projects.swift:64-88`; `Backup/BackupRestoreRun+CoreTypes.swift:118-122`; readers `Projects/ProjectDetailView.swift:59`, `Projects/Services/ProjectActivity.swift:36`, `Projects/ProjectSessionDetailView.swift:119`, `Projects/Services/ProjectCheckInSave.swift:21`, `Services/MCPServer/MCPNotebookTools+Projects.swift:155`.
- Fix: relink `session.project` through `index.related(CDProject.self, id: dto.projectID)` like the other children, plus a one-time repair for sessions with `project == nil` and a matching `projectID` (any Replace since the archive format began has left some).

### 8. A guide's notebook that has its own class but has never shared it can join another guide's class, and her own attendance then goes into that class (Likely)
The 2026-10-29 fix (`leadsItsOwnClass`) refuses only when a lead-guide row exists; with no row at all it answers false and the join goes through, writing an assistant row. From then on `CDAttendanceStore` routes every mark she takes for her own children into the shared store (the other guide's class), and the orphan guard stops filing anything she creates (it requires the lead-guide role). When she later presses Leave, the purge of that zone deletes those marks.
- Scenario: a co-teacher runs the full Cosmic Daybook for her own room (students in her private store, sharing never set up) and opens another guide's invitation in the notebook rather than the Daybook Assistant.
- Where: `Sharing/ClassroomLeave.swift:80-83`; `Attendance/Store/CDAttendanceStore.swift:70-77`; `Sharing/SharedStoreOrphanGuard.swift:132`; `Sharing/ClassroomSharingService.swift:261-273`.
- Fix: in `leadsItsOwnClass` (or `acceptShare`), also refuse when the private store holds students (`Self.holdsClassroom(privateStore, in: context)`), with the same "open it in the Daybook Assistant" message.

### 9. Back Up Now copies the finished archive with a plain `copyItem` on the main thread, with no check of the copy (Sure)
The writer builds a verified archive in the temp folder, then `SettingsViewModel.performExport` copies it into the iCloud Drive Backups folder with `FileManager.copyItem`. If the disk fills, iCloud Drive is mid-eviction, or the app is killed during the copy, a truncated file sits under the real backup name; nothing verifies it and nothing removes it. The copy is synchronous on the main actor, so the UI freezes for the duration of a photo-bearing backup. On iOS the fallback loads the whole archive into memory (`Data(contentsOf:)`) for the file exporter. Everything the automatic path gets right (temp file, verify, coordinated replace) is bypassed here.
- Where: `Settings/SettingsViewModel.swift:125-131, 181`; the good path `Backup/Archive/BackupWriter+VerifiedArchive.swift:28-62, 117-125`.
- Fix: hand `exportBackup` the final destination (`uniquedURL` in the folder) so the writer's own path produces the file in place; keep temp-then-copy only for the Save panel and file exporter, and do that copy with `UbiquitousFile.coordinatedCopy` off the main actor.

### 10. Replace clears a type the archive has no rows for, with nothing to put back (Sure)
Two ways in. (a) `LessonRecallCheck` has no `since` in the entity table (`firstFormat` 0), though recall checks joined the backup after the v19 bump and before v20: a Replace from a v17, v18 or early-v19 backup clears every recall check and restores none. (b) An entry that fails to decode is skipped with a warning and its payload field stays empty; `deleteAll` doesn't know and clears the type anyway. For a required type such as Student, one unreadable row empties the roster. The preview shows "-25" with no "+" and a warning, and Restore Now stays enabled. Same family as the 10-29 fix, one level down.
- Where: `Backup/BackupEntityTable.swift:213`; `Backup/Archive/BackupImporter.swift:181-194`; `Backup/Helpers/BackupPreviewAnalyzer.swift:95-103`; `Backup/RestorePreviewView.swift:147-153`; `Backup/BackupService+Helpers.swift:77`.
- Fix: `deleteAll` clears only the types the decoded archive actually holds rows for (the source knows which optional fields are nil and which entries decoded); refuse a Replace when a required type's entry was skipped; set `since: 20` on LessonRecallCheck meanwhile (confirm the exact first format from git before setting it).

### 11. A tick is lost when the ticked to-do is deleted or cleared before the Mac has told Tide (Sure)
At the end of a run `state.keep(only:)` forgets every to-do the fetch didn't return, and a deleted to-do is never judged. The Tide action stays open forever; nothing says so. (The known Tide row "deleting a linked to-do leaves its Tide item open" covers the plain delete; this is the tick-then-clear case, which is routine.)
- Scenario: Tide is closed or the Mac is asleep. Friday the guide ticks "Order bead chains" on the iPad. Monday she presses Clear Completed on any device.
- Where: `Services/Tide/TideSyncEngine.swift:128`; `Services/Tide/TideTodoStore.swift:64-67`; `Todos/Views/TodoMainView.swift:236-242`; `TodoMainView+BatchOperations.swift:51`.
- Fix: in `TideSyncService.observeTodos`, when the DidChange notification carries deleted to-dos that are completed and linked (deleted objects' attributes are still readable there), record `id → tideLink` in a `pendingTicks` map in `TideSyncState`; `carryTicks` ticks those by address and drops them on success or a permanent refusal. Remote deletes arrive through the history processor without values, so also keep an `agreedOpen` entry whose to-do vanished while completed until the tick goes across.

### 12. Automatic-backup failures are silent: nothing in the app reads the result (Sure)
`lastBackupEvent` and `lastBackupResult` are set and read by nobody. A device whose every automatic backup fails (chosen folder revoked, Keychain key unreadable after a device-to-device restore, an encode failure on one malformed row) just logs. The dashboard's "backup due" line is computed from the newest file across every device's folder, so a Mac that still backs up hides an iPad that has failed for weeks.
- Where: `Backup/Core/AutoBackupManager.swift:449-483`; `Settings/Dashboard/SettingsDashboardViewModel.swift:58-63`; `AutoBackupFolders.mostRecentBackup`.
- Fix: surface a failure from an automatic trigger as a Settings attention item per device ("This iPad's automatic backup hasn't worked since …"), and base `backupDue` on this device's own folder.

## Backups: writing

### 13. The guide is never told that lesson files, documents and story PDFs aren't in a backup (Sure)
The writer puts the note in the export summary, but the manual export discards it (`_ = try await coordinator.exportBackup(...)`), and `BackupSummaryView` is only shown for restores. The Backups card mentions photos only. The photo note says "Includes 12 note photos" without saying 40 more were left out because they weren't downloaded.
- Where: `Backup/Archive/BackupWriter.swift:239-247`; `Settings/SettingsViewModel.swift:119`; `Settings/DataManagement/DataManagementGrid.swift:66-68`; `DataManagementPanel+AutoBackupCard.swift:58-66`; `Backup/Archive/BackupPhotos.swift:85-101`.
- Fix: keep the export summary on success as the restore does, or add the files line to the Backups card; make the photo note say "12 of 52".

### 14. A backup of a half-downloaded notebook can still get in, and then trims the good ones (Likely)
Three ways around the 2026-10-05 fix. (a) `waitsForFirstDownload` only holds for 24 hours after arming; after that, with the download still pending (syncs stuck for days on school Wi-Fi are on record), every change-gated trigger writes a partial notebook into this device's folder and `trimAfterBackup` deletes the oldest complete ones. (b) `liftForSession` fires on a momentary `.noAccount` at launch (finding 26); `isPending()` is then false for the whole session while the download proceeds. (c) Manual and MCP `create_backup` are never held, and the receipt says "Backup written" with no hint the notebook is still downloading; that file is never trimmed and "Restore last automatic backup" may point at it.
- Where: `Backup/Core/AutoBackupManager.swift:517-523`; `Services/Sync/FirstDownloadGate.swift:33-35`; `Services/MCPServer/MCPNotebookTools+AppServices.swift:32`.
- Fix: for automatic triggers keep holding while `isPending()` regardless of age, but write into a quarantined name (`Partial-…`) that trimming ignores and the newest-backup lookup skips; for manual and MCP, add a warning line to the receipt while the gate is armed; don't lift the hold for the session on a single `.noAccount` answer.

### 15. The backup encryption key can fork on a new device, making backups from one side unreadable on the other (Sure; known from the 10-29 report, still unfixed)
New iPhone, iCloud Keychain not yet synced, Back Up Now (not gated): `fetchOrCreateKey` finds nothing and mints key B. When key A arrives, the two synchronizable items collide and one wins; every backup made with the loser fails with "locked with a key that isn't on this device" on every device.
- Where: `Backup/Core/BackupEncryptionKeyStore.swift:43-64`.
- Fix: before creating, wait briefly for iCloud Keychain and refuse to mint while a first download is pending; or key the item with a creation stamp and keep both keys for reading.

### 16. Paging by offset with no sort order can drop a row from one backup (Likely, rare)
`fetchAndTransformInBatches` reads 1,000 rows a page with no sort descriptor. A delete committed by a CloudKit import between page N and N+1 shifts the rows, and offset 1000 skips one. The streaming path catches a save between types and falls back to one pass, but a save inside one type's paging is invisible to both. Notes, attendance and presentations are the exposure; the next backup has the row again, but a restore from that one loses it.
- Where: `Backup/BackupService+DataCollection.swift:93-96, 121-122`.
- Fix: fetch the type's object IDs once and page with `SELF IN %@`, or sort by `id` and page by `id > last`.

### 17. A kill mid-write leaves a hidden `.partial-UUID` file that nothing ever removes (Sure)
`writeVerifiedArchive` removes the temp only on a thrown error. The Mac quit path terminates the process after 25 s; an iPad can be suspended during a scene-phase export. Each leftover is a full-size hidden archive in iCloud Drive; `trim` and every listing skip hidden files, so they accumulate forever. (The albums shelf has the cleanup the backups lack: `AlbumICloudShelf.swift:342-349`.) A photo-heavy notebook on a slow Mac may also never finish inside 25 s, so quit backups silently never succeed.
- Where: `Backup/Archive/BackupWriter+VerifiedArchive.swift:37, 57-60`; `AutoBackupAppDelegate.swift:28, 90-95`; `CosmicDaybookApp+Startup.swift:78-88`; `Backup/Core/AutoBackupFolders.swift:154-158`.
- Fix: on each export, delete `.<prefix>-*.partial-*` in the device folder older than an hour; consider raising the quit limit or skipping photos at quit.

### 18. "Restore last automatic backup" can quietly offer an older file than the newest (Sure)
`mostRecentBackup` lists with `.skipsHiddenFiles`, and an iCloud file not yet downloaded on this device exists only as a hidden `.name.icloud` placeholder. On the iPad, the Mac's newer backups are invisible, so the iPad's own older file is presented as "most recent" with no note.
- Where: `Backup/Core/AutoBackupFolders.swift:186-217`; `Utils/Files/UbiquitousFile.swift:45-56`.
- Fix: list placeholders too, take the newest by timestamp, and `ensureLocal` it before the preview.

### 19. Restoring a backup overwrites this device's backup settings, including the automatic-backup switch (Sure)
`autoBackupEnabled`, `autoBackupScheduledEnabled`, `autoBackupIntervalHours` and `autoBackupRetentionCount` are carried and applied with `.replace`. A Replace from a backup made while automatic backups were off turns them off on the restoring device; the interval loop is re-armed only by the card's `onChange`, so a restored interval doesn't take effect until relaunch.
- Where: `Backup/Core/BackupPreferencesService.swift:62-69, 160-167, 241-258`; `DataManagementPanel+AutoBackupCard.swift:71-72`.
- Fix: treat the four backup switches as device-local, and call `startScheduledBackups` after `applyPreferencesDTO`.

### 20. Dates lose their fractional seconds in every backup (Sure, low)
`JSONEncoder.dateEncodingStrategy = .iso8601` writes whole seconds. Rows made within one second can swap order after a restore, and "newer wins" checks compare a truncated date to a stored full one.
- Where: `Backup/Archive/BackupWriter.swift:484`; `Backup/BackupRestoreRun+LaterTypes.swift:320-322`.
- Fix: a `.custom` strategy writing `withFractionalSeconds`; the reader accepts both if switched the same way.

### 21. The size estimate on the Backups card counts 15 of 82 types (Sure, display only)
- Where: `Backup/BackupSizeEstimator.swift:60-75`.
- Fix: count every `BackupEntityTable` name, plus the photo folder's bytes when photos are on.

## Backups: restore

### 22. The Merge preview counts 15 of the ~80 backed-up types (Sure)
`analyzeMergeMode` hand-lists Student, Lesson, LessonAssignment, Note, the two calendar types, meetings, community topics, attendance, work completions and the project types; the digest keeps ids for only those. Work, check-ins, presentations, recall checks, to-dos, supplies, needs, schedules, stories, book club, guardians, album notes and the rest are invisible: a Merge of a backup that holds thousands of work records shows "Adding: 0" and "Nothing would change," and the guide confirms blind.
- Where: `Backup/Helpers/BackupPreviewAnalyzer.swift:180-227, 272-327`; `Backup/Helpers/BackupPreviewDigest.swift:104-139`; `Backup/RestorePreviewView.swift:68-73, 82-86`.
- Fix: iterate `BackupEntityTable.entities` as the Replace analysis does; the digest can take every row's id through `BackupRowDTO` as `BackupImporter+RecordIDs.swift:25` already does.

### 23. The iCloud wait subscribes after the save, so a quick restore ends with a false "still syncing" warning after 30 seconds (Sure, low)
The `Task` meant to subscribe before saving doesn't start until the current main-actor turn suspends, which is first at `await cloudExportWait.value`, after the save. A small restore's export can finish before that.
- Where: `Backup/BackupService+Restoration.swift:143-150, 153, 176, 391-393`.
- Fix: create the `messages` sequence synchronously before the save and hand it to the task, or judge by the store's export watermark.

### 24. A Replace from a backup older than 2026-10-11 brings back project check-in work without its type, and nothing repairs it again (Likely, low)
The importer writes `sourceContextTypeRaw` as the backup had it (nil for Uniform check-in follow-ups saved before 2026-10-11). The repair is behind a per-device flag set long ago, and the restore aftercare reruns the note-link and day-mirror repairs but not this one. Those rows show in neither the project nor its check-in.
- Where: `Backup/Import/BackupEntityImporter+Work.swift:45`; `Services/Migrations/DataCleanupService+ProjectWorkContext.swift:64-78`; `Backup/BackupService+RestoreAftercare.swift`.
- Fix: drop the flag and run the repair every launch (after the first its predicate matches nothing), or call it from the aftercare.

## Sync status and history

### 25. On iPhone and iPad the keep-alive can let the app sleep before a mark has gone (Likely)
The guide's marks are created in the private store and only later moved into the share by the orphan guard. In the notebook build any store's successful export clears `unsentSince` (the per-store check is `#if ASSISTANT_APP` only), so a private-store export that starts after the save ends the wait while the shared store's export, the mark the Assistant needs, is still running; and the notebook installs the keep-alive with no `isBusy`/`waitForWork`, so leaving the foreground never waits for the orphan guard's filing. `SiriExportWatch.ends` has the same any-store rule.
- Scenario: she marks a child, locks the iPad; the 25-second task ends on the first export; iOS suspends; the mark sits on the iPad until the next open.
- Where: `Services/Sync/UnsentChangesKeepAlive.swift:89-97, 127-131`; `AppCore/AppServicesLauncher.swift:114`; `Siri/SiriSyncKeepAlive.swift:95-100`; `Attendance/Store/CDAttendanceStore.swift:70-77, 222-223`.
- Fix: track `unsentSince` per store from the saved objects' `objectID.persistentStore`, clear only the matching store's on its export, and in the notebook pass hooks that wait for the orphan guard's flush, as the Assistant does.

### 26. A momentary "no iCloud account" at launch lifts the first-download gate for the whole session (Likely, rare trigger, the 2026-09-28 outcome)
`watchForFirstDownload` asks `accountStatus()` once; on `.noAccount` it lifts the gate for the session and runs what the gate held. `isPending()` then reads false everywhere: the launch zone repair, the orphan guard, the template seeder, the one-time repairs (finding 58), automatic backups (finding 14b). The 2026-10-10 hunt showed a Mac opening at login gets `noAccount` for a moment while the account is still signing in, which is why `noteSetupWithoutAccount` asks twice a minute apart.
- Scenario: Re-download from iCloud (or a new Mac), the download runs long, the Mac restarts with the app opening at login; the account comes up, the download resumes unguarded, and the zone repair finds rows whose CKShare hasn't landed and moves them into the classroom share.
- Where: `Services/Sync/CloudKitSyncStatusService+FirstDownload.swift:36-43`; `FirstDownloadGate.swift:33-34, 57-59`; `Services/Migrations/MigrationRunner.swift:47`; `Sharing/SharedStoreOrphanGuard.swift:192`; `+AccountReadiness.swift:171-182`.
- Fix: reuse the double check (ask again after `waitBeforeAccountRecheck`, lift only if still `noAccount`), and undo the lift when `CKAccountChanged` reports an account.

### 27. Events replayed at `configure` are dated "now," not when they happened (Sure, cosmetic)
Buffered launch events go through `handleCloudKitEvent` at configure time with `Date()`. An import that finished seconds before the window appeared reads "Last synced: now," and a failure's "since" is the configure time.
- Where: `+EarlyEvents.swift:86`; `+EventHandlers.swift:243, 303-304`.
- Fix: carry the event's `endDate` in `CloudKitEventValues`.

### 28. The last second of Sync History is lost at quit (Sure, low)
`SyncEventLogger` writes one second after the last row; `flushPendingSave()` has no caller. A "sync stopped" row logged right before the guide quits is the row she'd open Sync History for.
- Where: `Services/Sync/SyncEventLogger.swift:147-152, 156-167`; `+EventHandlers.swift:357-374`.
- Fix: call `flushPendingSave()` from the lifecycle observers that already flush the sync date.

## Classroom share: setup and filing

### 29. An assistant added as "View only" can mark attendance on her phone, and the marks never reach the guide (Likely)
The Mac's Add Member picker offers "View only" (`readOnly`). The Daybook Assistant decides what she may do from the membership row's role (`ClassroomPermissions.canWrite`), never from the share participant's permission (no reader of `currentUserParticipant?.permission` anywhere in `Daybook Assistant/`). The grid lets her mark; the save lands in her shared store; the attacher's `share(_:to:)` is refused with permissionFailure (code 10), which isn't a stop reason, so the pass falls back to one by one, every record fails, and they stay "waiting for the share" for good.
- Where: `Settings/Classroom/ClassroomMembersSheet.swift:197-204`; `Sharing/ClassroomPermissions.swift:21-31`; `Sharing/ClassroomShareAttach+Server.swift:87-101`.
- Fix: drop "View only" from the picker (the share's permission has no use in this app's model), and have the Assistant read the participant's permission once and show a read-only state.

### 30. Set Up Classroom Sharing on two of the guide's devices at once makes two share zones (Likely, rare)
Preflight reads the server's zone list once, then scans every classroom record and asks CloudKit which are shared (seconds to minutes on a real class). `shareCreationBlocker`, asked right before `share([seed], to: nil)`, checks sync state only, not the server. The attach lock is per process, and the Set up button has no platform guard. If the second preflight ran before the first share zone reached the server, both create one, and every device then refuses with "iCloud already has 2 classroom shares."
- Where: `Sharing/ClassroomSharingService+Setup.swift:161-164, 168-186, 189-215`; `Settings/Classroom/ClassroomSharingView.swift:181`; `Sharing/ClassroomShareAttachLock.swift:16`.
- Fix: call `fetchServerShareZoneNames()` again inside `createPinnedShare` immediately before the share call and refuse if it's non-empty; show the button only on macOS, as the doc comment ("Run once, on the Mac") intends.

### 31. A share that exists on the server but whose pin never saved can't be adopted: setup refuses forever (Likely, rare)
If the app quits between `createShareOffMain` returning and `savePin` committing, the server holds one share zone with the seed student and no device holds a pin. Every later preflight hits the `!serverZones.isEmpty` branch and throws `otherShareZonesExist(1)`. There is no repair path in Settings.
- Where: `Sharing/ClassroomSharingService+Setup.swift:180-184, 206-213, 264-269`.
- Fix: in preflight, when the server holds exactly one share zone, the local private store holds that CKShare, and there is no pin, pin it and continue as a resumed setup.

### 32. Records left in a dead share zone count as "not in the share," and "Add them to the share" can never add them (Sure, low)
`countInShare` counts a record as shared only when its zone is the pinned one; a record in a leftover zone from the 2026-09 incident counts as outside. Setup's attach first drops anything in any share, so the button reports "0 items added" and the card keeps saying N aren't in the share.
- Where: `Sharing/ClassroomSharingService+Contents.swift:64-68`; `Sharing/ClassroomShareAttach.swift:125-132`; `Settings/Classroom/ClassroomSharingView.swift:111-115, 168-169`.
- Fix: count "in another share" as its own number and say so; those records need the release's copy-and-delete, not `share(_:to:)`.

### 33. A notebook joined as an assistant never files its shared-store marks into the share explicitly (Likely, low)
`attachNewRecordsToClassroomShare` is called only from the Daybook Assistant. A notebook in the assistant role saves marks into its shared store and leaves the zone to Core Data, the pre-2026-09-28 behavior the Assistant was moved off. With a stale second share present it's a coin toss.
- Where: `Attendance/Store/CDAttendanceStore+ClassroomShare.swift:9-16`; `CDAttendanceStore.swift:218-224`.
- Fix: refuse joins in the notebook altogether (finding 8 covers the dangerous half), or call the same attach after the notebook's attendance saves when the role is assistant.

### 34. The Sharing Model text is four types behind the code (Sure, doc)
`CLAUDE.md` says "Classroom share (11 types, schema 18)" and "over all eleven share types"; the code has 15 (schema 22) with the four Timetable types of schema 20. Every code list agrees: `CoreDataStack+Model.swift:82-123` is the single source read by `ClassroomShareScope`, `SharedStoreOrphanGuard+Records`, `DedupShareBoundary`, `BackupWriter` and `AssistantSave`; the Assistant target compiles all 15 entity files.

### 35. Two running copies of the Mac app share one waiting list in UserDefaults and can clobber each other's entries (Likely, rare, low)
Both read-modify-write `classroomSharePendingAttach`; a save in the secondary copy interleaved with a pass's `forget` in the primary can lose the secondary's entry. The window is microseconds.
- Where: `Sharing/SharedStoreOrphanGuard+WaitingList.swift:58-67, 99-100`.

## Remove Last Year and the sharing settings

### 36. The Remove Last Year sheet can be opened with sync stopped and then has no way out (Sure for no exit; Likely for the hang)
`load()` reads the whole share first and only then computes the blocker ("iCloud sync has stopped on this Mac"), so the read runs regardless of sync state; the read is `fetchShares(matching:)` over every student and mark, which waits on the mirroring delegate. While `.loading` the footer is `EmptyView()`: no Cancel, no `.cancelAction`, so Esc does nothing and the macOS sheet has no close box.
- Where: `Settings/Classroom/ClassroomReleaseModel.swift:43-56`; `Settings/Classroom/ClassroomReleaseSheet.swift:249-276`; `Sharing/ClassroomShareRelease+Live.swift:137-147`; `+Rows.swift:37`.
- Fix: run `ClassroomShareRelease.blocker` before reading (show it in `.ready` with an empty preview), give `.loading` a Cancel button, and put a time limit on the read with a plain message.

### 37. A change to a departed child's record made on the Mac during the run is silently lost (Likely)
The run can take many minutes (one batch per departed child, then slices of 500 marks, each waiting on iCloud). The sheet is modal only to the Settings window; the main window still works. Step 3 (`checkCopies`) is the only point that carries the original's values to the copy; step 4 (`deleteOriginals`) deletes without looking again. An edit landing on the original in that window goes with the delete; the roster dedupes by id, so she can't tell which copy she edited.
- Where: `Sharing/ClassroomShareRelease+Run.swift:158-198, 290-304`; `+Vanished.swift:18-42`.
- Fix: in `deleteOriginals`' own `perform`, compare each original with its copy again and either carry the change over before deleting or throw a new RunError ("changed while this ran") so the batch retries.

### 38. A run stopped partway plus a child who comes back leaves her twice in the notebook, for good (Likely)
A run stops after steps 1–3 for a departed child. Before the guide finishes it, the child re-enrolls. Now the shared original `belongs`, so `moves(in:)` skips the whole group and the private twin is never planned. `DedupShareBoundary.spansShare` keeps both copies forever, the card drops to nothing once Finish clears the flag, and `mixedDuplicates` is computed but shown nowhere. Edits to the private copy never reach the assistants.
- Where: `Sharing/ClassroomShareRelease.swift:131-146`; `Settings/Classroom/ClassroomLastYearCard.swift:13-16`; `Sharing/ClassroomSharingService+Contents.swift:70, 153`; `Services/Migrations/DedupShareBoundary.swift:30-42`.
- Fix: let the planner emit a "twin cleanup" move when a shared source belongs and a private twin exists, and surface `mixedDuplicates` on the card until it's done.

### 39. Remove Last Year trusts the September 1 fallback for the school-year start (Sure path, Likely trigger)
`ClassroomShareScope()` marks itself `isProvisional` when the synced start hasn't reached the device (a new Mac before iCloud key-value storage arrives). The orphan guard and setup treat that specially; the release preview, the card's count and `blocker` ignore it. Only `cutoffBlocker`'s 14-day window stands in the way, which misses a class that began more than two weeks before Sep 1.
- Where: `Sharing/ClassroomShareRelease+Preview.swift:60-69`; `+Live.swift:28-47`; `Sharing/ClassroomShareScope.swift:30-48`.
- Fix: in `blocker`, refuse while `ClassroomShareScope().isProvisional` ("Your school-year start hasn't reached this Mac yet. Open Settings › School year, then try again.").

### 40. "Stop sharing…" gives no feedback, stays enabled, and keeps an old error (Sure)
No working state: a second click runs a second `removeAllMembers` against a share whose tag the first save just changed, which can show "Couldn't stop sharing. iCloud didn't answer." after the first succeeded. `errorMessage` is never cleared on this path. The members sheet's "Remove everyone…" does this right.
- Where: `Settings/Classroom/ClassroomSharingView.swift:242-268` vs `ClassroomMembersSheet.swift:242-262`.
- Fix: an `isStoppingSharing` state (spinner, disabled), `errorMessage = nil` before the call.

### 41. The "deletes awaiting iCloud" list can trap the card on "Finish Removing Last Year…" (Likely, rare)
`awaitingGone` is cleared only when the server no longer holds every record on it. (a) A run stopped between steps 4 and 5, then Re-download from iCloud and the child returned meanwhile: the records now belong and are never planned again, so every Finish waits 10 minutes and stops with "iCloud took too long." (b) The share zone is gone: `records(for:)` answers `zoneNotFound` per record, which `waitFor` treats as non-transient, so every run ends "Couldn't hear back from iCloud" with the flag kept. Nothing in the UI can clear the flag.
- Where: `Sharing/ClassroomShareRelease+Run.swift:102-111`; `+Finish.swift:16-49`; `Services/Sync/CloudKitServerCheck.swift:56-75`; `+RunError.swift:79-83`.
- Fix: treat `.zoneNotFound` as "gone"; before waiting on leftovers, drop any record the fresh plan holds or that now belongs; after a timeout on leftovers alone, clear the list and the flag with a plain line.

Smaller: the preview line "N attendance marks from before that day, for children no longer in your class" also counts this year's marks of a child whose record was deleted (`+Preview.swift:76-85`); `ClassroomSharingView.refreshContents` returns early unless the scene is active, so the status banner and the Last Year card can stay empty until the next phase change (`ClassroomSharingView.swift:83-86`).

## Daybook Assistant

### 42. On a network where iCloud stays unreachable, the stack is rebuilt every 10 minutes all session, and each rebuild tears the whole UI down (Likely)
First mark: `latestForAttach` times out (15 s), rest 30 s, second failure, `sendLooksStalled`, `sendStalled`, `rebuildStack`. Rounds keep coming every 30–120 s, so 10 minutes later the next failed round rebuilds again. Each rebuild on a joined phone sets `phase = .starting` and `coreDataStack = nil`, and the root view replaces the tabs by the stack's identity: "Starting…" flashes mid-arrival; the attendance view model is recreated (Close Arrival's Undo, the last tap's undo and the day she navigated to are lost); the Mail composer and the Classroom and sign-in sheets are dismissed mid-use (a half-written front-desk email vanishes and no send is recorded); Restock check-off ticks and their Undo go. The rebuild cannot help on such a network.
- Where: `Daybook Assistant/Sync/AssistantShareAttacher+Rounds.swift:65-72`; `+Class.swift:99-111, 126`; `AssistantBootstrapper.swift:254-256`; `AssistantRootView.swift:41-45`; `AssistantAttendanceViewModel.swift:108-116`; `AssistantFrontDeskMail.swift:46-60`; `AssistantRestockModel.swift:60`; `Sharing/ClassroomShareAttach+Server.swift:34, 57`.
- Fix: rebuild for a stall at most once per launch unless a send succeeded since the last one, never while a sheet is up or within the first minutes of arrival, or only in the background. At minimum, keep the old screen until `install` has the new stack.

### 43. Leave's "N marks haven't reached your guide" counts name rows, Restock lines and front-desk send records as marks (Sure)
`unsentMarks` uses `pending.count`, and the list holds every record `AssistantSave` filed: her `ClassroomPerson` row, `SupplyTransaction`/`OrderItem` from Restock, `AttendanceEmailSend`. One unsent mark plus a name row reads "2 marks haven't reached your guide yet."
- Where: `Daybook Assistant/Sync/AssistantBootstrapper+Leave.swift:107-113`.
- Fix: resolve the URIs and count only `AttendanceRecord` entities, or word it "changes."

### 44. Marks saved right after joining, before the share record is in the store, wait up to 10 minutes with nothing retrying them when it arrives (Likely, narrow)
`attachNewRecordsToClassroomShare` finds no share, returns everything as `left` with `noConnection == false`, so the backlog rests 1, 2, 4, 8, 10 min. A successful import only retries when `isOffline`, and `readClassShare` finding the share refreshes the service but doesn't touch the attacher. A name row written at setup on a stack that has no share yet hits this every time.
- Where: `Attendance/Store/CDAttendanceStore+ClassroomShare.swift:91-94`; `Daybook Assistant/Sync/AssistantShareAttacher+Rest.swift:32-34`; `AssistantStack.swift:77`; `+Class.swift:322-324`.
- Fix: in `readClassShare`, when the pinned share is found and `pendingCount > 0`, call `retryWaiting()`; or make `onSharedStoreSynced` retry whenever the last failure was "no share."

### 45. Under a filing hold, Leave › Wait returns at once with the wrong advice (Sure; follows from 5)
`sendUnsentMarks` calls `retryWaiting()`, the pass exits at `filingWaits()` within milliseconds, `isRunning` goes false, and `afterWaitNote` says "Check that this iPhone is online."
- Where: `Daybook Assistant/Sync/AssistantBootstrapper+Leave.swift:159-169`.
- Fix: if `AssistantStack.filingStopReason != nil`, return a note saying iCloud isn't ready on this phone yet (or quit and reopen when the hold is a dead delegate).

## Tide to-dos

### 46. A repeating Tide to-do can be ticked twice and roll two periods ahead (Likely)
Morning: she ticks a weekly to-do on the iPad; the Mac is asleep. Afternoon: she sees it still open in Tide and ticks it there; Tide rolls it to next week. The Mac wakes: the copy is done here, the action is open (found by its notebook line, with the new due), `agreedOpen` is true, so `complete_action` again; Tide rolls it a second week; `store.reopen` gives the copy the two-weeks-out date.
- Where: `Services/Tide/TideSyncEngine+Steps.swift:72-75, 110-116`.
- Fix: remember the action's `due` beside `agreedOpen`; in the `(true, action?)` case, if the action's due has moved past the agreed one, treat the tick as already carried and reopen the copy with the new date.

### 47. To-dos from Tide can be lost for good if the notebook stops mid-run after marking them (Likely)
Order in `perform`: `showTideActions` inserts the new to-dos (unsaved), `markLinkedActions` writes `notebook:<uuid>` into each action's Tide note (one call each), and only then `store.save()`. If the app dies in between, Tide's actions name to-dos that never existed here: `showTideActions` skips them forever and `adoptSentActions` has nothing to adopt. On a first run with many Tide to-dos the window is seconds long.
- Where: `Services/Tide/TideSyncEngine.swift:120-132`; `+Steps.swift:252-277`.
- Fix: `store.save()` and `persist(state)` right after `showTideActions`, before any note is marked (as `send` saves after each add).

### 48. Tide actions with a future start date show here as due-now to-dos (Sure, low)
`showTideActions` takes every `state == "open"` action regardless of `started`; `TideAction` doesn't decode `start` at all, and `followTide` ignores it.
- Where: `Services/Tide/TideTools.swift:8-33`; `+Steps.swift:224-241, 92-96`.
- Fix: decode `start`, set `scheduledDate` from it on show and in `followTide`, or skip not-yet-started actions until their day.

### 49. A child's page claims Tide to-dos by first names that are ordinary words (Sure, low)
`TideNameMatcher` adds a child's bare first name as a form whenever it is unique in the roster and matches it as a whole word anywhere in title or note. A Mark, May, Will, June, Grace, Hope or Rose puts "Mark attendance sheets" or "Order paper in May" on that child's page.
- Where: `Services/Tide/TideMatching.swift:101-103, 108-115`; `Students/Detail/StudentTideTodosSection.swift:80-83`.
- Fix: match a bare first name only in the note's "For …" line, or only when capitalized mid-sentence.

### 50. "Tide is still opening" waits up to three minutes, and Low Power Mode pauses the sync behind an "Up to date" line (Sure, low)
`.stopped(.stillOpening)` is shown as a problem and nothing is scheduled before the 3-minute timer (the message says "in a moment"). With Low Power Mode on, `perform` returns before touching the status, so the last "Up to date with Tide." stays on screen while ticks pile up unsent.
- Where: `Services/Tide/TideSyncService.swift:245, 269-271`.
- Fix: for `.stillOpening` and any `isTemporary` request a run after `timing.change`; when deferring, show "Paused while in Low Power Mode."

### 51. A Tide to-do whose note couldn't take the notebook line is closed here when reworded or moved in Tide, then comes back as a new one (Likely, low)
When `update_action` refuses the marker, the to-do is known by address only. A reword or move in Tide changes the address; `currentAction` finds nothing, so `judge` ticks the copy off here, and `showTideActions` brings the reworded action in as a second, fresh to-do.
- Where: `Services/Tide/TideSyncEngine+Steps.swift:55-60, 76-84, 271-275`.
- Fix: when the address lookup fails for a to-do in `unmarkedLinks`, leave it unjudged rather than closing; retry marking across sessions.

## The Core Data stack

### 52. A notebook that joined someone else's classroom can lose unsent marks: an incoherent shared store is moved aside without a word (Likely, rare trigger)
On the notebook (not the Assistant), a shared store whose physical schema is short a column (an older build's half-finished migration) is quarantined and rebuilt from CloudKit. For a co-teacher's notebook joined as an assistant, her marks and name rows not yet exported are gone, with no message and no offer. Nothing re-arms a first-download hold for the rebuilt shared store either.
- Where: `AppCore/Persistence/CoreDataStack+SchemaVersion.swift:258-271`; `CoreDataStack+OrphanCleanup.swift:645-671`; `CoreDataStack+Stores.swift:435-448`.
- Fix: quarantine only when the shared store is a mirror of other people's data this device never wrote to (lead guide, or empty attendance and person tables); otherwise throw `storeSchemaIncoherent` as the Assistant does, so the error screen's Re-download carries its warning.

### 53. Two writers build their background context straight from the container, so they save with no author and the error merge policy (Sure mechanism; consequences Likely)
`CoreDataStack.newBackgroundContext()` sets `mergeByPropertyObjectTrump` and the process's `transactionAuthor`. Two writers bypass it: the Assistant's Leave deletes and Remove Last Year's copies, nudge and deletes. (Eight more call sites use the container's context for reads only.) With the default `NSErrorMergePolicy`, a save whose row was touched by a CloudKit import between fault and save fails with "could not merge changes" instead of merging, so a Leave or a release batch stops on a conflict the rest of the app would resolve. With a nil author, the history processor treats the transactions as its own and the other copy of the Mac app never merges them until relaunch.
- Where: `Attendance/Store/CDAttendanceStore+ClassroomShare.swift:143-154`; `Sharing/ClassroomShareRelease+Run.swift:141, 224, 251, 302`; `AppCore/Persistence/CoreDataStack+Contexts.swift:51-56`; `Services/Sync/PersistentHistoryProcessor+StoreHistory.swift:78-80, 250`.
- Fix: take the context from the stack, or set both `mergePolicy` and `transactionAuthor` where only the container is at hand (as `DeduplicationCoordinator.swift:210-217` does).

### 54. A second copy launched during a migration is told, after 10 seconds, to quit the copy that is mid-migration (Likely, Mac only)
`claimStoresForLaunch` waits 10 s for the surgery holder, then throws `storeInUseByAnotherCopy`, whose text says "Quit the other copy, then open Cosmic Daybook again." A big notebook's lightweight migration plus its pre-migration copy can take longer; the guide then kills the migrating copy. The data survives (the next launch migrates again), but the advice is the wrong one.
- Where: `AppCore/Persistence/CoreDataStack+Stores.swift:204-220`; `CoreDataStack.swift:449-451`.
- Fix: wait without a short limit while the surgery lock is held, or word the error as "another copy is updating your notebook; wait for it."

### 55. Re-download and the error-screen restore leave whole copies of the old notebook on disk for good (Sure; disk and privacy, not data loss)
`resetStores` removes only `private`, `shared`, `unified` and their `-wal`/`-shm`. Left behind forever: `*.premigration.sqlite` (a full copy before every migration, never removed after success), `shared.sqlite.incoherent` quarantines, every `Set aside …` folder from `FreshNotebookRestore`, and the `.private_SUPPORT` external-data folder. On an iPhone that is a second classroom-sized copy beside the fresh one.
- Where: `AppCore/Persistence/CoreDataStack+Stores.swift:234-256`; `CoreDataStack+OrphanCleanup.swift:214-245, 645-671`; `Backup/FreshNotebookRestore.swift:176-180, 258-281`.
- Fix: delete the pre-migration copy once the migrated store has loaded and been stamped; have `resetStores` remove the `_SUPPORT`, `.premigration` and `.incoherent` siblings; trim "Set aside" folders after N days or show them in Settings.

### 56. Debug only: asking for dependencies before the notebook opens trips an assertion (Sure, latent)
`AppDependencies.defaultValue` falls back to `notOpenYet`, which calls `getSharedCoreDataStack()`, which asserts whenever the stack is still nil. The "Opening your notebook…" view doesn't read the environment today; the first view that does will crash Debug runs at launch.
- Where: `AppCore/AppDependencies.swift:340-345`; `AppBootstrapping+SharedStack.swift:68-82`.
- Fix: drop the assertion (keep the fault log), or make `defaultValue` an in-memory stand-in.

## Migrations and cleanups

### 57. A safe-mode launch marks every one-time launch repair "done" on an empty temporary store (Likely, low today)
When the stores fail to open, the bootstrap falls back to an in-memory stack without throwing, `initError` stays nil, the services launcher counts the store as loaded, and the post-launch migrations run against the empty store. Nothing checks `inMemoryStoreSession` (only the warning banner reads it). The gate isn't armed (the store file exists), so the check-in link repair, note scope index, note links, project work context, attendance lock carry-over and restock levels flags are all set, and the check-in grace ledger is wiped. On the next good launch those repairs are skipped for good on this device. Low today because every repair has already run on Danny's devices; it bites a device whose first-ever run lands in safe mode.
- Where: `AppCore/AppBootstrapping+CloudKit.swift:111-116`; `AppCore/AppServicesLauncher.swift:90`; `AppCore/AppBootstrapper.swift:116, 209-223`; `Services/Migrations/MigrationRunner.swift:262-270`; `DataCleanupService+CheckInAndNoteRepairs.swift:81`.
- Fix: at the top of `runPostLaunchMigrations` and `runLaunchBatch`, return when the session is in-memory, as the Sample Class already never runs the pass.

### 58. The same flags are set on an empty store when the first download is lifted for the session (Likely, low)
Every one-time repair gates on `isPending()`, which reads false after `liftForSession()` (finding 26) while the gate stays armed; they run on the empty store and mark themselves done. The guide signs in later, the notebook downloads, and the device never runs them. Lifting is right for zone repair and template seeding; it's wrong for "done once" flags.
- Where: `Services/Migrations/DataMigrations.swift:97`; `+NoteScopeIndex.swift:93`; `+ProjectWorkContext.swift:70`; `RestockLevelBackfill.swift:41`; `Attendance/Store/AttendanceDayLocks+LegacyKeys.swift:73`.
- Fix: give the one-time repairs a stricter check (the gate armed, not merely pending), or don't set a flag when the store holds no students or work.

### 59. The lesson name merge deletes a duplicate track step without remapping marks that named it (Sure path, no visible effect today)
Unlike `TrackTitleMerge.mergeSteps`, which returns a remap, the lesson name merge leaves `trackStepID` on presentations, assignments and work pointing at the deleted step. The only reader that matches by `trackStepID` also matches by lesson id, so nothing shows wrong now; it becomes a bug the day a reader keys on the step alone.
- Where: `Services/Migrations/DataCleanupService+LessonNameMerge.swift:345-351`; `+TrackTitleMerge.swift:185-207, 288-315`.
- Fix: reuse `repointTrackReferences`' remap here.

## Looked at and found sound

So the next hunt need not re-read them:
- **Share pin discipline**: no `.first` on the owner side; `classroomShare(among:)` matches the pin only; `unshared` before every `share(_:to:)` and again inside `attach`; a throwing `fetchShares` counts as "wait," never "unshared"; every call fetches the server's copy with short timeouts.
- **The waiting list**: cap only drops while unshared, after pruning deleted, shared and out-of-scope records; provisional scope keeps last-year-looking marks; `forget` is stamp-matched; Siri hands permanent IDs after the save. Every filing source (restore, MCP, CSV import, calendar, timetable, bookings, Restock, names, the email log, day locks) saves on the view context into the private store.
- **Store boundary**: the only relationships touching share types are Supply ↔ SupplyTransaction (both shared); the Timetable types use string keys. All 15 share types are in every list.
- **Remove Last Year's five steps**: copies assigned to the private store, server confirmation before any delete, `awaitingGone` confirmed per batch, resume from any step, one run per process, backup check covers twins. Student and AttendanceRecord have no relationships, so attribute copies lose nothing.
- **Names**: writes gated one at a time with the zone lookup off the main thread; two devices converge on the oldest row by (`createdAt`, `id`); the stand-in owner never attributes.
- **Sync events**: one stream per process started before the stores open; finished events buffered (cap 100) and replayed in order; per-store health keyed by store identifier; stale successes can't clear a stop; the same event twice is idempotent. Only a successful import or export stamps a sync.
- **Account change** drops dates, watermarks, store health and non-attach stops; keeps filing holds. **First download** opens only on the private store's own import, persisted across relaunch. **Persistent history** positions per store, nil-author treated as own, purge per store behind min(own export start, 180 days); every consumer fails open on an expired token. **Dedup coordinator** arms on either store's import, serialized with the launch pass.
- **Backup archive**: hidden temp file, full re-read verification (decrypt, manifest, per-entity line counts, photo count), coordinated rename; an encode failure for any type aborts the whole export. Coverage: 82 types plus 3 deprecated plus 8 tombstones = the model's 93; the schema 19–22 fields round-trip; `BackupCoverageTests` tripwires hold. Schedule: interval-0 crash fixed, overdue at launch runs after a minute, hot and Low Power deferral, retention never below one and never another device's folder.
- **Restore**: parents before children; every to-one relationship optional; clear plus import in one save; unsaved edits saved first; a failure discards only the restore's changes; older archives 17…44 open with lenient DTOs and `BackupFieldsAddedLater`; the names' newer-wins and merged-on-Replace from 10-29 hold; the first-download gate is checked at preview and import; decode runs off main and all Core Data work is on the main actor in one turn.
- **Dedup survivor rules**: `precedesAsCanonical` and `identityPrecedes` the same on every device; `DedupSyncState` wired into every pass; every deduplicated entity with a Cascade relationship re-parents children first; the Assistant runs no dedup; sync off means no dedup.
- **Launch repairs**: only the pre-open SQLite repairs and one seeder fetch run before the UI; the rest 3 s after `UIReady` at utility priority on a tagged background context under `holdingPasses`; every repair writes only rows that differ; `saveFolds` and `runLaunchBatch` roll back on failure and keep the flags unset; `NotebookJunkCleanup` is manual, Mac-only, bounded to previewed IDs, behind a verified backup.
- **Schema guard**: pre-load stamp only on non-migrating stores, restamp after load with the exclusive lock, a secondary copy never migrates, an older build is refused by stamp; the coherence cache can only cause an extra check. Primary-key repair only raises `Z_MAX`. The process lock's shared→exclusive conversions are atomic.
- **Daybook Assistant**: the invitation inbox holds one delivered before any service exists; a second guide's class is refused; the attach rounds never drop `fresh`, honor `notBefore`, and the watchdog token drops a let-go call's results; history trim per store with no token; every `CDAttendanceStore` write stamps attribution and is behind `canWrite(on:)` which reads the share's locks; new records always go to the shared store; Leave waits for the attacher and deletes only records CloudKit confirms are in no share; the rebuild path can't loop (each cause has its own 10-minute window; its UI cost is finding 42).
- **Tide**: transport timeouts and plain messages, no retry storm, token never logged, Keychain item this-Mac-only; iPhone, iPad, Debug and tests never talk to Tide; one run at a time; the sync's own writes don't retrigger; refusal wordings match Tide's source; sending saves after every `add_action`; Merge never blanks a link.

## What next

Fix in this order: 1–12 (the ones that lose data or trap the guide), then 13–24 (backups), 25–28 (sync), 29–41 (sharing), 42–45 (Assistant), 46–51 (Tide), 52–59 (stack and migrations). Finding 2 needs one Apple fact checked first: whether a share whose zone has no objects left is dropped by NSPersistentCloudKitContainer. Findings 1 and 19 were design choices; Danny settled them on 2026-11-02 (Merge keeps the newer record, backup switches stay each device's own).

All 59 are now fixed. What is left is checking on the devices, one Tide row each:
- [Merge restore on the sharing Mac, with the Assistant's phone open](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20do%20a%20Merge%20restore%20on%20the%20sharing%20Mac%20with%20the%20Assistant%27s%20phone%20open%2C%20then%20check%20nothing%20changed%20since%20the%20backup%20went%20back%20and%20her%20marks%20stayed): after the next roll-out, check that nothing changed since the backup went back and her marks stayed.
- [Replace restore on the sharing Mac](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20do%20a%20Replace%20restore%20on%20the%20sharing%20Mac%20with%20the%20Assistant%27s%20phone%20open%2C%20then%20check%20her%20class%20never%20empties%20and%20she%20can%20still%20mark%20attendance): after the next roll-out, check that her class never empties and she can still mark attendance.
- [A Tide-made to-do edited on the iPad](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20on%20the%20iPad%20change%20the%20title%20and%20due%20date%20of%20a%20to-do%20that%20came%20from%20Tide%2C%20then%20check%20both%20changes%20show%20in%20Tide%20once%20the%20Mac%20has%20synced): after the next roll-out, change a Tide-made to-do's title and due date on the iPad and check both show in Tide once the Mac has synced.
- [The Assistant after a stall on the school Wi-Fi](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20Assistant%20build%20is%20on%20her%20phone%2C%20watch%20it%20on%20the%20school%20Wi-Fi%20when%20iCloud%20stalls%3A%20it%20should%20say%20what%27s%20happening%2C%20recover%20by%20itself%2C%20and%20rebuild%20at%20most%20once): once the next Assistant build is on her phone, watch it on the school Wi-Fi when iCloud stalls; it should say what's happening, recover by itself and rebuild at most once.
- [Danny's decision on Merge and records with no change date](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Decide%20whether%20a%20Merge%20restore%20should%20also%20keep%20edits%20to%20work%2C%20presentations%2C%20lessons%20and%20meetings%20made%20since%20the%20backup%2C%20which%20needs%20a%20change%20date%20on%20those%20records%20%28a%20schema%20change%29): decide whether a Merge should also keep edits to work, presentations, lessons and meetings made since the backup, which needs a change date on those records (a schema change).
