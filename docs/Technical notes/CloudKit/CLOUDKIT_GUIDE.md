# CloudKit Guide

How Cosmic Daybook and the Daybook Assistant sync through CloudKit, how to tell
whether sync is healthy, and the rules that keep it that way.

**Last Updated**: September 28, 2026 (iOS/macOS 27 SDK; main app targets 27.0, Daybook Assistant 18.0)

The short rules live in `Cosmic Daybook/CLAUDE.md` → CloudKit Notes. This
document explains the design behind them.

## 1. The stack

Sync is `NSPersistentCloudKitContainer` end to end
(`AppCore/Persistence/CoreDataStack.swift`). There is no `CKSyncEngine`, no SwiftData and
no hand-written `CKOperation` code. That is still Apple's recommended setup for
a Core Data app that shares records. SwiftData can't share at all, and
`CKSyncEngine` is for apps that don't use the container.

| | |
|---|---|
| Container | `iCloud.DanielSDeBerry.MariasNoteBook`, a literal in `CloudKitConfigurationService.containerID`. Use `CloudKitConfigurationService.container`, never `CKContainer.default()`: the assistant's bundle ID resolves to a different, empty container. |
| `private.sqlite` | Configuration `Private`, `databaseScope = .private`. The lead guide's own records, and the share they own. |
| `shared.sqlite` | Configuration `Shared`, `databaseScope = .shared`. Only records from shares this device *accepted* (an assistant's view of the classroom). |
| Public database | Not used. |

**Environments.** The `CLOUDKIT_ENVIRONMENT` build setting (`Development` or
`Production`) sets both the `com.apple.developer.icloud-container-environment`
entitlement in both apps and the `CloudKitEnvironment` Info.plist key the app
reads (`AppCore/Persistence/CloudKitEnvironment.swift`). Development-signed builds obey it;
TestFlight and App Store builds are always Production. Each environment is its
own notebook on a device:
- Production's store files live in a `Production/` subfolder of the store
  directory; Development's stay where they always were. Sample Class belongs to
  neither and stays in the base folder.
- Keys that describe one store's sync state get the environment in their name
  (`CloudKitEnvironment.scoped`): history positions, purge and export dates,
  the first-download gate, the sync event and error logs, the backup change
  token, the check-in repair flag, the user record name, the classroom attach
  list. Development keeps the bare key, so a Development build finds its
  notebook untouched.
- A schema run (`-InitializeCloudKitSchema`) is refused by a Production build;
  build with `CLOUDKIT_ENVIRONMENT=Development` for one.

**Where things stand (2026-09-28).** The notebook moved to Production that day,
in seven steps (Mac first, the Assistant tested in a simulator, then the iPhone
and iPad together):
- The Mac, iPhone and iPad run Production. Before the switch, the 14 old zones
  in Production's private database (about 11,800 records from TestFlight-era
  builds) were deleted, and the notebook came across by restoring the 16:53
  backup in Replace mode.
- Production's private database holds exactly two zones: the default zone
  (9,023 records) and the classroom share `DB5879EF-D0F4-467E-A1EA-E51092B48BD7`
  (3,224 records: 38 students, 3,107 attendance records, 40 days off, 39 day
  locks). Checked on copies of the iPhone's and iPad's stores.
- Development is frozen at the backup, on every device, as the way back:
  installing a Development build opens that notebook untouched. Nothing writes
  to it any more.
- The plan's three open questions were answered: the Assistant's explicit share
  assignment works (see §3); iCloud pushes reach development-signed Production
  builds (an iPhone mark reached the iPad); and restore dropped only the one
  supply transaction, which backups now carry (v31).
- **Any new CloudKit field must be deployed to Production before any device
  runs the build that writes it.** Production can't create fields on the fly,
  so those records would fail to upload. That covers the Assistant too, whose
  attendance lives in the share.
- To check what a device holds, copy its store over USB:
  `xcrun devicectl device copy from --device <udid> --domain-type
  appDataContainer --domain-identifier DanielSDeBerry.MariasNoteBook --source
  "Library/Application Support/DanielSDeBerry.MariasNoteBook/Production/private.sqlite"`
  (plus `-wal`/`-shm`). This works on the development-signed Release builds.
  The copies hold children's data, so move them to the Trash when done.

**Entity routing** (`CoreDataStack+Model.swift`, schema 9):
- The classroom share holds exactly what the Daybook Assistant needs:
  `Student`, `AttendanceRecord`, `NonSchoolDay`, `SchoolDayOverride` and
  `AttendanceDayLock` (`sharedEntityNames`, 5 types). They belong to both
  configurations.
- Everything else — lessons, tracks, notes, work, `ClassroomMembership` — is
  Private only (`privateEntityNames`). Until schema 9 the share held 33 types,
  and the Student ↔ StudentTrackEnrollment relationship dragged a child's
  tracks, steps and lessons into it; that relationship is gone (enrollments keep
  `studentID`).
- New records land in the first store added, which is the private one. The lead guide wants that.
- The assistant doesn't, so `CDAttendanceStore` assigns her records to the shared store explicitly.

**Store options** (`CoreDataStack+Stores.swift`): history tracking and remote-change notifications are on for every store, along with automatic lightweight migration.

**If loading fails**, `AppBootstrapping+CloudKit.swift` falls back in order:
1. The CloudKit stack.
2. The same files without CloudKit.
3. A unified local store.
4. In-memory.

**Schema initialization:** `initializeCloudKitSchema` runs only in a DEBUG
Development build with `-InitializeCloudKitSchema`. Deploy the development schema to production in the
CloudKit Console before shipping a model change. A monotonic
`currentSchemaVersion` guard (`CoreDataStack+SchemaVersion.swift`) stops an
older build from migrating a newer store backwards.

## 2. Sharing: one classroom, one share

The notebook has exactly two zones: the private default zone, and one
classroom share holding the share types above, this school year's only (see
"Who is in the share" below).

- **Creating the share — once, on purpose.** Settings → Classroom → **Set Up
  Classroom Sharing** (`ClassroomSharingService+Setup.swift`). It refuses unless
  this is the lead guide's device, the first download has finished, and the
  server holds no share zone (`fetchServerShareZoneNames`). It then creates a
  Core Data–managed per-zone share (`com.apple.coredata.cloudkit.share.*`)
  seeded with a student, shares every student, attendance record, school-calendar
  day and day lock in chunks of 200 (`ClassroomShareAttach`), pins the zone and
  reports the counts. Run again while the pinned share is the only share zone on
  the server, it adds whatever of those types is in no share — the way to finish
  a setup that stopped partway. Nothing else creates a share: the launch-time and
  orphan-guard auto-create are gone, because they minted zones whenever a store
  merely *looked* unshared (13 zones in Development by 2026-09-28).
- **The pin.** The lead guide's `ClassroomMembership.classroomZoneID`, written
  by setup (`ClassroomRepository.pinClassroom`) and, on an assistant's device,
  by accepting an invitation — updating the row, not adding one. One accessor,
  `CDClassroomMembership.current(in:)` (newest `modifiedAt`, then `joinedAt`),
  feeds the role, the pinned zone and the repository.
- **Choosing the share.** A store can hold several shares, and
  `fetchShares(in:)` has no order. `CDClassroomMembership.classroomShare(among:in:)`
  returns the pinned one and nothing else: no pin, or no share matching it,
  means "not shared yet". Never take `.first`.
- **Invite preflight.** Manage Sharing (the app's own members sheet, on every
  platform) goes through `shareForInvitations`, which refuses
  unless the pinned share exists and holds students, and shows what it holds.
- **Inviting (Mac).** `ClassroomMembersSheet` is the Mac's own members sheet.
  It looks the person up with `shareParticipants(for:)`, adds them, and saves
  with `persistUpdatedShare(_:in:)`.
  - Adding someone already on the share is refused locally.
  - The server's `participantAlreadyInvited` (iOS/macOS 26) becomes "already invited".
  - "Remove Everyone" removes participants but keeps the share: a new one
    would be a second zone.
- **Inviting (iOS).** The same members sheet, with the share link sent by
  `ShareLink`. Not `UICloudSharingController`: its Stop Sharing deletes the
  share for the owner and can't be hidden (2026-10-06). Stop Sharing on every
  platform removes everyone and keeps the share (`removeAllMembers()`).
- **Invite-only.** The share has no public permission. Since iOS/macOS 26 a
  share rejects access requests by default (`allowsAccessRequests == false`),
  and the server won't even confirm to an uninvited person that it exists.
- **Owner name.** `com.apple.developer.icloud-extended-share-access` =
  `InProcessShareOwnerParticipantInfo` is in the main app's entitlements.
  Without it, iOS/macOS 26 return nil for the owner's name and contact fields,
  and an assistant's Classroom Members list shows "Name not shared" for the
  guide. The App ID must have the capability, or signed builds fail
  provisioning. Apple's terms: participant names and addresses are displayed,
  never stored.
- **Accepting.** `acceptShareInvitations(from:into: sharedStore)`, then the
  accepted zone is pinned on the assistant's membership row.
  - iOS: the scene delegate (`ShareAcceptanceAppDelegate`).
  - macOS: `application(_:userDidAcceptCloudKitShareWith:)`.
  - Invitations that arrive before the service exists wait in `ShareInvitationInbox`.
- **Leaving.** `purgeObjectsAndRecordsInZone(with:in:)`.

**Never move a record that's already in one share into another** with
`share(_:to:)`. On 2026-09-27 that failed with 134410 → 134421 and killed the
mirroring delegate for the session. `ClassroomShareAttach.unshared` filters
every attach down to records in no share.

### Who is in the share: this school year only (2026-09-30)

`ClassroomShareScope` is the one rule, and every path that puts records into the
share filters through it (setup, "Add Them to the Share", the orphan guard):

- **Students:** enrolled, or departed during this school year
  (`dateWithdrawn` on or after its first day), or with any attendance from this
  year (covers a missing or placeholder departure date). A child who leaves
  mid-year stays: off today's roll, still on the days she was here.
- **Attendance:** dated on or after the school year's first day, for a student
  who belongs. Ids compare case-insensitively.
- **Everything else** in the share (days off, extra school days, locked days,
  the front-desk email) always belongs.

The first day is the school-year start (`YearPlanStaleness.currentYearStart`),
which is one synced setting (`SchoolYearSync`, §7).

**Taking last year out: `ClassroomShareRelease`.** Nothing leaves the share on
its own. Once a new school year begins, Settings › Classroom shows how many
records from before it are still shared, and on the Mac (a Debug build takes
`-AllowShareReleaseOnIOS` for rehearsals) **Remove Last Year from the Share**
opens a preview: each departing child with her date and record count, the
earlier attendance of children who stay, and a checklist. It refuses to start
unless sync is healthy, online and caught up (0 pending), this is the lead
guide's only running copy, and no attendance sits in the two weeks before the
school-year start (a start set later than the real first day). It then makes a
manual backup and checks it (`BackupReader.verifyStructure`, student and
attendance counts equal to the store) before touching anything.

There is no API to unshare a record, so each is **copied**: an identical object
(same `id`, every attribute, `copyAttributes`) goes into the private default
zone, and the shared original is deleted only after the copy is on the server.
Each batch (a departed child with her marks first — the smallest is the canary —
then earlier-year attendance in slices of 500) runs five steps: insert the
copies; confirm them **on the CloudKit server** (`CloudKitServerCheck`, not an
export event: on 2026-09-30 a store read healthy while its exports were refused);
check each copy is still here and bring over anything the original changed;
delete the originals; confirm on the server that they're gone. iCloud always
holds at least one copy, and other devices receive the copy before the delete.
A run stopped anywhere leaves at most both copies; the next run finds the
private copy ("twin") and only deletes. A copy that disappears (a device on an
old build deduplicating it away) stops the run with the original kept.

Each save waits until no export of the notebook is running, and the run checks an export
starts after it (`ClassroomShareExportActivity`); if none does, one harmless change (a
private copy's `modifiedAt`, a millisecond on) schedules one. In the 2026-09-30 rehearsal a
save made mid-export was left out of it with nothing scheduled after, and the batch's deletes
sat unsent until the app was relaunched. A server check that fails on the network, is
throttled, or doesn't answer in 90 s is asked again until the step's 10-minute limit.

**Rehearsed 2026-09-30** on two simulators signed into a test account (a pretend class of 25
students and 2,532 marks across two school years): both runs moved 3 departed children and
2,034 old marks; a force-quit mid-run was finished by the next press; the other device,
reopened every 35 s mid-run, held up to 500 marks on both sides of the share at once and its
dedup kept both every time, then settled on every record exactly once with the share holding
this year only. Putting last year back (start date earlier, "Add Them to the Share") worked.

Two guards make the in-between safe on the guide's other devices, and must be
on every device before any release: **dedup never deletes either copy of a
record held both in and out of a share** (`DedupShareBoundary`), and **the
launch orphan cleanups only strip a student id missing on passes a day apart**
(`OrphanStudentGrace`).

**If a release goes wrong:** stop; nothing is lost locally (at worst both copies
exist, and dedup keeps both). If sync stopped, quit and read the log, then Reset
Local Cache on the Mac or a **Merge** restore of the checked backup — never
Replace. Last year's records can always go back: move the school-year start
earlier and "Add Them to the Share" attaches them (attaching unshared records is
the safe path).

## 3. The Daybook Assistant

An iOS-only companion (`Daybook Assistant/`, deployment target iOS 18.0). It
compiles about 40 of the main app's files by path and builds the same
`CoreDataStack` and `ClassroomSharingService`.

- **What it touches.** It reads students, attendance (with notes), the
  school calendar and locked days, and writes attendance for any day the guide
  hasn't locked. The header's ‹ › arrows step through school days, the date
  opens a picker for any day, and Today comes back.
- **Its new marks go into the classroom share explicitly** after the save that
  creates them (`CDAttendanceStore.attachNewRecordsToClassroomShare`): the
  pinned share, or the only share in its shared store. CloudKit accepts that
  from a participant: in the Production move's Assistant test (2026-09-28) a
  note logged `AttendanceShare: attached 1, failed 0` and reached the Mac.
- **What it skips.** It runs no history processor and no orphan guard (`#if !ASSISTANT_APP`).
- **Which membership rows it reads.** Only assistant rows, so a lead-guide row
  synced from the same Apple Account can't make it file attendance as a guide.
- **Status line** (`AssistantSyncStatusView`).
  - It says "All marks sent to iCloud" only after a successful `.export` event
    for the shared store that *started after* the last save touching that store.
  - The last save and last export are kept in `@AppStorage`, so marks left
    unsent by a closed app still show as unsent.
  - A failed export shows "Not sent yet".
  - On iOS 26.4.0 it also asks for an update. That release dropped CloudKit's
    silent pushes, so changes arrived only on relaunch; 26.4.1 fixed it.
- **Minimum OS.** Because the target is iOS 18.0, files the assistant compiles
  must not use iOS 26 or 27 API without `#available`.

## 4. Persistent history

`PersistentHistoryProcessor` (an actor, main app only) keeps **one token per
store**. A single token once silently stopped reading the other store.

It reads transactions whose author isn't `"CosmicDaybook"`, then:
- posts scoped change notifications,
- requests a scoped dedup pass,
- leaves merging to `automaticallyMergesChangesFromParent`.

**Purging.** History is deleted before `min(last successful export start,
now − 180 days)`, at most every 60 days. Purging before the mirroring delegate
has exported can reset sync and resurrect deletes.

**Debouncing.** Three layers:
- 400 ms in `CoreDataStack`,
- the actor's "another pass" flag,
- a 5 s dedup debounce.

## 5. Monitoring

`CloudKitSyncStatusService` watches:
- iOS 27 typed messages: `.remoteChange`, `.storesDidChangeAsync` and
  `.eventChanged`. Each stream is read in order by one main-actor task.
- The classic `NSManagedObjectContextDidSave` notification, for local saves.

On the 27.0 SDK the object-ID save messages (`.didSaveObjectIDs`,
`.didSaveObjectIDsAsync`) arrive twice per save, and the async one never
arrives for main-queue contexts. So save observers stay on the classic
notification, or on `.didSave` for main-queue contexts, as
`SharedStoreOrphanGuard` does.

**What it records:**
- The last successful export start, which gates history purging.
- A dead mirroring delegate (setup failure, 134421, 134406, or "never successfully initialized").
- Retry state with backoff.

**Where it shows up:**
- **Settings → Data & Sync → iCloud**: status, a dead-delegate banner, and Sync Now.
- **Settings → Classroom**: what the classroom share holds, a read-only count
  of classroom records outside it, Set Up Classroom Sharing, role, members and
  the invite sheet.
- **Settings → Database → Maintenance**: Reset Local Cache and Re-sync from iCloud.
- **The MCP `sync_status` tool**: the same state as the service.

Two numbers are not what they sound like:
- **"Sync Now"** only saves the view context.
- **"Pending changes"** counts local saves since the last event, not records waiting to upload.

## 6. Records join the share when they're created

`SharedStoreOrphanGuard` watches view-context saves — every place that
creates a student, attendance record, school-calendar day or day lock saves
there: the screens, MCP writes, restore, CSV import and
`SchoolCalendarService`. It takes the classroom types the save *inserted* into
the lead guide's private store and attaches them to the pinned share. Before
the pin arrives (a new device still downloading, or the iPad before the Mac's
setup reaches it) they wait in a persisted list
(`UserDefaultsKeys.classroomSharePendingAttach`, capped at 2,000) and go in on
the next remote change, launch or first-download finish that finds the pin.
Setup on this device shares everything, so it clears what it found in the list,
and it makes a second pass for records created while it ran.

**Nothing sweeps.** `SharedStoreZoneRepair` looked for records that *looked*
unshared after every launch, import, dedup and share change. Mid-download a
zone's rows land before its CKShare, so they read as orphans: on 2026-09-28 a
post-reset pass moved 4,003 of them into the wrong share. It and the Repair
Sync Errors button were removed. Settings shows drift read-only; the explicit
setup action is the only thing that fixes it.

**What stops an attach:** `FirstDownloadGate` (nothing until the first
private-store import after a reset or on a new device), a dead mirroring
delegate, and CloudKit's share-export timeout. What failed stays in the list.

## 7. iCloud Drive and key-value storage

**Files.** PDFs, backups and note photos live in the ubiquity container. Go
through `UbiquitousFile`:
- a placeholder counts as present,
- reads download first,
- writes, moves and deletes are coordinated.

**Preferences.** `SyncedPreferencesStore` (see
[Plan - iCloud preference sync.md](<../../Plans/Plan - iCloud preference sync.md>)).

**The school year (2026-09-30).** The start month and day, and whether day
counters start over on it, are one setting for the class, synced by
`SchoolYearSync` through key-value storage. UserDefaults stays the local copy
every reader uses (`FloridaGradeCalculator`, `YearPlanStaleness`,
`SchoolYearCounters`, MCP); iCloud's values are copied in at launch and on each
external change. Only an explicit edit publishes (Settings, the MCP tool, a
backup restore) — never a launch — except that the Mac fills an empty iCloud
with its own values; an iPhone or iPad only adopts. The live instance never
starts under unit tests (a Mac test run is signed into the guide's iCloud). The
day counters' epoch is derived, not stored: the current school year's first day.

**Account state.** Use `CKContainer.accountStatus` / `.CKAccountChanged` for
sync health. `ubiquityIdentityToken` describes iCloud *Drive*, which a user can
turn off while CloudKit keeps working.

## 8. Checking that sync works

1. **Signed in.** Every device uses the same Apple Account, with iCloud on.
2. **Round trip.** Change something on one device. **Settings → Data & Sync → iCloud** should show a recent successful sync on both.
3. **Assistant.** Mark attendance in the Daybook Assistant. The line should go from "Sending to iCloud…" to "All marks sent to iCloud", and the mark should appear on the guide's devices.
4. **Verbose logging.** Add the launch argument `-com.apple.CoreData.CloudKitDebug 1` (3 is the most detailed).
   - Filter Console for `com.apple.coredata` and the app's `sync` category.
5. **CloudKit Console** (icloud.developer.apple.com):
   - Open the container.
   - Query the **Private** database's `com.apple.coredata.cloudkit.share.*` zones.
   - Use **Telemetry** / **Logs** for request and error rates.
   - The private database should hold exactly two zones: the default zone and one classroom share.
     A new share zone appearing means something created a duplicate share.
6. **Apple's references:**
   - [TN3163: Understanding the synchronization of NSPersistentCloudKitContainer](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer)
   - TN3164 (debugging the container)
   - TN3162 (CloudKit throttles)

**Last resort.** Settings → Database → Maintenance → Reset Local Cache. The
first download afterwards is gated (see §6). Nothing attaches or seeds during it.

---

## Related Documentation

- `Cosmic Daybook/CLAUDE.md`, CloudKit Notes: the rules in brief
- [Plan - iCloud preference sync.md](<../../Plans/Plan - iCloud preference sync.md>): iCloud KVS preference sync
- [ARCHITECTURE.md](../ARCHITECTURE.md): architecture guide


## Working notes from CLAUDE.md

Moved verbatim from `Cosmic Daybook/CLAUDE.md` on 2026-10-02 so that file keeps only the rules every session needs. Dates in the notes are when each change landed.

### CloudKit Notes

- **Environments (2026-09-28):** the `CLOUDKIT_ENVIRONMENT` build setting picks Development or Production for both apps (entitlement + `CloudKitEnvironment` Info.plist key; `AppCore/Persistence/CloudKitEnvironment.swift`). Each environment is its own notebook on a device: Production's store files live in `Production/` under the store directory, and keys describing one store's sync state go through `CloudKitEnvironment.scoped` (history positions, purge/export dates, first-download gate, sync logs, backup change token, check-in repair flag, user record name, classroom attach list, lock carry-over flag). Development keeps today's paths and bare keys, so it stays untouched as the fallback. Sample Class is in neither. A new per-store key must be scoped too. TestFlight/App Store builds are always Production whatever the setting says.
- Container: `iCloud.DanielSDeBerry.MariasNoteBook` — a literal in `CloudKitConfigurationService.containerID`, deliberately NOT derived from the bundle ID: the assistant companion app has its own bundle ID but shares this container. Reach it through `CloudKitConfigurationService.container`; never `CKContainer.default()`, which resolves from the bundle ID.
- Two persistent stores: private (teacher data) + shared (classroom data)
- Schema changes must be additive-only after CloudKit deployment
- All models use string-based foreign keys for sync compatibility
- **Attendance lives in the shared store** so the assistant companion app can write it (both steps landed; step 2 was 9e4fa1d4, 2026-08-30). `AttendanceRecord.recordedBy`/`modifiedAt` attribution is stamped by `CDAttendanceStore` (the chokepoint that also enforces `ClassroomPermissions.canWrite`, and assigns an assistant's new records to the shared store explicitly); records are created lazily on first mark, never in bulk on screen-open; the old `AttendanceRecord.notes` ↔ `Note.attendanceRecord` relationship is gone (it would cross store configurations) and `Note.attendanceRecordID` is the only link; both dedup passes share `AttendanceDeduplication.wins` (marked > latest `modifiedAt` > lowest id).
- **A screen built from a one-off fetch must listen for imports.** It won't see another device's change until it reloads: on 2026-09-28 an iPhone attendance mark reached the iPad's store, but the open roll only showed it after leaving the screen and coming back. Use `onPresentationDataChange(WhenVisible)` with entities from `PersistentHistoryProcessor.presentationEntityNames`; add the entity to that set if it isn't there (AttendanceRecord and AttendanceDayLock joined it for the roll and the Mac heatmap).
- **Two zones: the private default zone and one classroom share (2026-09-28).** The share holds only `CoreDataStack.sharedEntityNames` — Student, AttendanceRecord, NonSchoolDay, SchoolDayOverride, AttendanceDayLock, AttendanceEmailSend, AttendanceEmailSettings — and nothing else; the Student ↔ StudentTrackEnrollment relationship that pulled tracks and lessons into it is gone (schema 9). **It is created once, on purpose,** by Settings → Classroom → Set Up Classroom Sharing (`ClassroomSharingService+Setup.swift`), which refuses unless this is the lead guide's device, the first download has finished and the server holds no share zone; nothing creates a share automatically any more. **The pin** is the current membership row's `classroomZoneID` (`CDClassroomMembership.current`, the one accessor; `ClassroomRepository.pinClassroom` writes it on setup and on accepting an invitation). `classroomShare(among:in:)` returns the pinned share or nil — never `.first`. Manage Sharing refuses unless the pinned share exists and holds students. **Never move records that are already in one share into another with `container.share(_:to:)`:** on 2026-09-27 moving 27 records between share zones failed with 134410 → 134421 and the mirroring delegate stayed dead for the session; `ClassroomShareAttach.unshared` filters every attach to records in no share.
- **Early pickups are on the record (schema 13):** `AttendanceRecord.leavesAt`, set from the attendance menu's Leaving Early… in both apps (`AttendancePickupSheet`, compiled into the Assistant by path) and written only through `CDAttendanceStore.updateLeavesAt`. A plan, not a mark: it leaves the status alone, Left Early still records when the child went (`leftAt`), and tiles and cards show "leaves 1:30" until then (`AttendanceRules.pickupText`). Offered today and ahead, never on a past day or for a child absent or gone. Reset Day clears it (Undo restores it), dedup keeps the losing copy's time, and it keeps a record from counting as blank. The Daybook Assistant reminds before each pickup (`EarlyPickupReminder`, 10 min unless changed, on by default; Classroom screen); the notebook doesn't ring. **Counts are who's in the room:** "here" in the tallies and the completion line is present + late (`AttendanceRow.isInRoom`), so a child marked Left Early leaves the count ("17 here (1 late) · 1 left early"); `isHere` still means came in, for welcome-backs and bells.
- **Back in Class (schema 14):** a child marked Left Early who comes back is brought back from the long-press/right-click menu's Back in Class (`AttendanceStatusMenu`, both apps), never by a tap: `statusAfterTap` returns nil for Left Early in both phases, so a stray tap can't wipe the day's times. `CDAttendanceStore.markBack` returns them to present or late, whichever they left from (`statusBeforeLeavingRaw`, written when Left Early is marked from present or tardy), keeps `markedAt` and `leftAt`, sets `returnedAt` (only on the day itself) and clears `leavesAt`. The trip shows as "out 11:15–12:40" (`AttendanceRules.tripText`) on cards, roomy phone tiles and the menu header; it needs `leftAt` on a present or late mark, which only Back leaves, so a stale `returnedAt` from an older build never shows. One trip per day: any other mark ends it, and leaving again shows the latest departure. Siri's "here" and MCP `mark_attendance` still mark a left-early child fresh (no Back there yet).
- **Attendance notes are on the record (schema 8):** `AttendanceRecord.note`, shared, written only through `CDAttendanceStore.updateNote`; the notebook and the companion edit it with `AttendanceNoteSheet`. `AttendanceNoteMove` (each launch, in `MigrationRunner`) carries any private Note still linked by `attendanceRecordID` onto its record and deletes it — an older build can still write one — and attendance dedup merges both records' notes. The companion also reads the school calendar (`SchoolDayChecker`) and takes no marks on weekends or days off.
- **Records join the share when they are created; nothing sweeps (2026-09-28).** `SharedStoreOrphanGuard` watches view-context saves (every creator of the share types saves there: screens, MCP, restore, CSV import, `SchoolCalendarService`) and attaches the share types a save *inserted* into the lead guide's private store to the pinned share (`ClassroomShareAttach`, chunks of 200, off the main actor). Before the pin arrives (a new device, or the iPad in the minutes before the Mac's setup reaches it) they wait in a persisted list (capped at 2,000, oldest first) and go in on the next remote change, launch or first-download finish that finds the pin; setup on this device clears what it found there. In the notebook a lead-guide membership row outranks a newer assistant row, so trying the Daybook Assistant on the guide's own Apple Account can't demote the notebook. The Daybook Assistant attaches its own new marks after saving (`CDAttendanceStore.attachNewRecordsToClassroomShare`: pinned share, else the only share) through `AssistantShareAttacher`: one pass at a time, and whatever didn't go in waits in a persisted, environment-scoped list (`Assistant.pendingShareAttach`, capped at 500) for the next save or launch. A failed pass rests the backlog (1 min, doubling to 10 while failures continue) and retries it on its own when the rest ends; a newly saved mark is always tried, one that goes in ends the rest early (once per rest), and coming back to the foreground retries everything waiting. `AssistantShareAttacherTests` runs the queue in memory with a stand-in share (the `attempt:`, `now:` and `sleep:` seams). **Leaving the foreground waits for the send (2026-09-29):** on iOS, both apps keep themselves awake after backgrounding (≤25 s, `UnsentChangesKeepAlive`) while a view-context save has no finished export that started after it, or the Assistant's attach pass is running; before, only Siri marks got background time, so a tap just before locking waited for the next launch. The Assistant reads students from the shared store only (`AssistantDayRoll.classroomStudents`), so an account that also keeps its own notebook never marks that notebook's children. `SharedStoreZoneRepair` and the Repair Sync Errors button are gone: sweeping for records that *looked* unshared is what split the classroom (a post-reset pass moved 4,003 mid-download rows into the wrong share). Settings → Classroom shows what the share holds and a **read-only** count of classroom records outside it; re-running setup (pinned share the only server zone) is the one explicit fix. **Nothing attaches during a first download:** `FirstDownloadGate` is armed when the stack loads with no private store file (Reset Local Cache, a new device) and opens on the first successful `.import` event *for the private store*; until then the guard waits and `BuiltInTemplateSeeder` does nothing. The seeder racing the download is what left ~4 copies of every template; `+SameSourceMerges` folds identical templates, reminders sharing an EventKit id, and events sharing an EventKit id + start.
- **This school year only, and taking last year out (2026-09-30).** `ClassroomShareScope` decides what belongs: enrolled students, students who left during this school year (`dateWithdrawn` on or after its first day, or any attendance this year), and attendance from the first day on; the other share types always. Setup, "Add Them to the Share" and `SharedStoreOrphanGuard` filter through it (a student *updated* in the private store — re-enrolled after leaving in an earlier year — is queued with this year's attendance). Nothing leaves the share on its own: `ClassroomShareRelease` (Mac only; Settings › Classroom) copies each out-of-scope record into the private default zone (same `id`, every attribute), confirms the copy **on the CloudKit server** (`CloudKitServerCheck`), re-checks it, then deletes the shared original and confirms that on the server — batch by batch, the smallest departed child first as a canary, after a verified manual backup, refusing to start unless sync is healthy and caught up, it's the only running copy, and no attendance sits just before the school-year start. **Never take a record out of the share any other way.** Two guards must be on every device first: dedup never deletes either copy of a record held both in and out of a share (`DedupShareBoundary`; identical attendance copies tie-break on the CloudKit record name), and the launch orphan cleanups only strip a student id missing on passes a day apart (`OrphanStudentGrace`, `UserDefaultsKeys.orphanStudentGrace`, cleared by Reset Local Cache). The Assistant pages no earlier than the share's first day with attendance and never marks a row whose child an import just deleted. Full design and recovery: `CLOUDKIT_GUIDE.md` §2.
- **One school year on every device (2026-09-30):** the start month/day and the day-counter mode sync through key-value storage (`SchoolYearSync`); UserDefaults stays every reader's local copy. Only explicit edits publish (Settings, `update_school_calendar`, a restore); the Mac seeds an empty iCloud, iOS only adopts; never started under unit tests. The counter epoch is derived (the current school year's first day), never stored.
- **The front-desk attendance email (schema 12):** whoever finishes the roll sends it, in either app, and everyone sees who did. `AttendanceEmailSend` rows (one per send; newest shown, "Sent 8:42 AM by Sarah") and one `AttendanceEmailSettings` row live in the classroom share, read and written only through `AttendanceEmailLog`. The guide still edits the email in Settings › Communication (`AttendanceEmailPrefs`, iCloud key-value, the guide's devices only); `AttendanceEmail.shareSettings` copies them into the row at launch and after edits (lead guide only, not during a first download) so the Daybook Assistant writes the same email to the same people (`AttendanceEmailReport.swift`, `AttendanceEmailLog.swift` and the two entity files compile into both apps). Apple never lets an app send mail unattended: a send is recorded when `MFMailComposeViewController` reports `.sent` or the Mac's `NSSharingService` reports it shared; otherwise (another Mail app, a Mail timeout) the screen asks "Did the email go?", and Mark as Sent covers telling the front desk another way. **The front desk needs it by a deadline** (9:00 unless changed; `AttendanceEmail.deadlineMinutes`, carried in the settings row): from 30 minutes before, both apps show it's due and, with children still unmarked, offer Close Arrival & Email (Assistant) / Mark Rest Absent & Email (notebook), which marks them absent after asking and opens the email; past it the control turns amber/orange and a later send reads "(late)" (`AttendanceEmailLog.urgency`, redrawn by an explicit-date `TimelineView`). Tardies after the email are the office's (children check in there), so nothing re-sends for them. `FrontDeskEmailReminder` (both apps) schedules two notifications per school day, a per-device lead time before the deadline (10 min) and at it, withdrawn once the day's email has gone; on by default in the Assistant, off in the notebook. A tap opens Attendance with the email ready (`NotebookNotificationTaps`, `ArrivalReminderTaps`).
- **Locked attendance days are shared records (schema 9):** `AttendanceDayLock` rows in the classroom share, read and written through `AttendanceDayLocks`; only the lead guide locks or unlocks, and `CDAttendanceStore` refuses every edit on a locked day for everyone (MCP `mark_attendance` says so). The old `Attendance.locked.<date>` key-value settings are carried into records once per device (after the first download) and after restoring an older backup; the keys stay for Development builds.
- **Persistent history purge policy:** never purge history the mirroring delegate may still need — that resets sync and can resurrect deletions. `PersistentHistoryProcessor.purgeOldHistory` only deletes transactions that predate BOTH the last successful `.export` event's start date (recorded by `CloudKitSyncStatusService`) and a 180-day retention window, at most every 60 days. Do not add token- or short-date-based purging.
- **Only the primary on-disk `CoreDataStack` creates a `PersistentHistoryProcessor`.** Sample Class / in-memory stacks must not — history tokens are per-store and all processors share one UserDefaults key.
- **History positions are per store.** A token read from a transaction covers only that transaction's store, and a fetch given a token ignores `affectedStores` (which narrows only a token-less fetch). So `PersistentHistoryProcessor` keeps one position per store identifier (`UserDefaultsKeys.persistentHistoryStoreTokens`, cleared by Reset Local Cache) and reads each store on its own; its old single token silently stopped reading whichever store did not hold the newest transaction. Never save a coordinator token or another store's token as a store's position. Pinned by `PersistentHistoryTokenScopeTests` and `PersistentHistoryStoreCursorTests`.
- **CloudKit schema:** after a model change, run a DEBUG *Development* build once with the `-InitializeCloudKitSchema` launch argument to mirror the model into the development schema, verify in CloudKit Console, then deploy to production before release.
- **iCloud Drive files (2026-09-27):** the managed PDF folders (`Documents/<Library> Files/`), backups (`Documents/Backups/`) and note photos (`Note Photos/` at the container root, outside `Documents/` so children's photos never show in Files/Finder) live in the ubiquity container; a note stores only the photo's filename. Go through `UbiquitousFile` for anything that touches them: on iOS a file from another device is a hidden `.<name>.icloud` placeholder until downloaded, so `fileExists` is the wrong test (`isAvailable`), anything that *reads* the bytes awaits `UbiquitousFile.localURL(for:)` / `ensureLocal` first, and writes, moves and deletes are coordinated. `PhotoStorageService.moveLocalPhotosToICloud()` (post-launch) moves photos taken before the change; reads check iCloud then the local folder. **Never orphan-clean the iCloud photo folder** — a photo arrives through iCloud Drive before its note arrives through CloudKit, so one device's store can't judge it; `cleanupOrphanedNoteImages` is local-folder only on purpose.
- **Account availability:** use `CKContainer.accountStatus` / `.CKAccountChanged` for CloudKit sync health, never `ubiquityIdentityToken` (that reports iCloud *Drive*, which users can disable while CloudKit keeps working). The ubiquity token remains correct for the iCloud Drive file-storage features.
- **Share owner info needs an entitlement (iOS/macOS 26+):** without `com.apple.developer.icloud-extended-share-access` = `InProcessShareOwnerParticipantInfo` CloudKit returns the owner's `CKUserIdentity` name and contact fields as nil. The main app declares it (2026-09-28); the App ID must have the capability or signed builds fail provisioning. Apple's terms: participant names/addresses are shown, never stored.
- **Typed Core Data messages (iOS 27):** `CloudKitSyncStatusService`, the restore export wait and `SharedStoreOrphanGuard` observe `.eventChanged`, `.remoteChange`, `.storesDidChangeAsync` and `.didSave` messages. Don't move save observers onto `.didSaveObjectIDs`/`.didSaveObjectIDsAsync`: on the 27.0 SDK they arrive twice per save (and the async one never for main-queue contexts). Files the Daybook Assistant compiles stay on classic notifications — its deployment target is iOS 18.0 (it warns on 26.4.0, whose dropped CloudKit pushes 26.4.1 fixed).

#### Known beta-SDK build warnings (Xcode 27 beta 1)

- `@Generable` macro expansions reference the deprecated `GenerationError.decodingFailure` internally. The warning comes from Apple's macro-generated code, not project source, and cannot be fixed here — re-check on each new Xcode 27 seed and drop this note once Apple fixes the macro.
- `SpeechRecognitionService.installRecognitionTap` suppresses the `installTap` deprecation via Swift 6.4's `@diagnose` attribute: the refined replacement (`installAudioTap`) delivers `AVReadOnlyAudioPCMBuffer`, which `SFSpeechAudioBufferRecognitionRequest.append` cannot accept in beta 1. Re-check each seed and migrate when Speech catches up.

#### Console log noise to ignore

These come from Apple's frameworks, not this app — they are not actionable in source:

- `updateTaskRequest called for an already running/updated task com.apple.coredata.cloudkit.activity.export.*` (subsystem `com.apple.BackgroundSystemTasks`, category `BGSTFramework`) — `NSPersistentCloudKitContainer` internals managing background export tasks.
- `updateTaskRequest failed for com.apple.coredata.cloudkit.activity.export.*` and `Error updating background task request: BGSystemTaskSchedulerErrorDomain Code=3` — same source; benign when sync is otherwise working.
- `It's not legal to call -layoutSubtreeIfNeeded on a view which is already being laid out.` (subsystem `com.apple.AppKit`, category `WarnOnce`) — AppKit/SwiftUI hosting internals on macOS 27 beta; no project code calls `layoutSubtreeIfNeeded`. Logged once per run.
- `XPC connection was interrupted` (subsystem `com.apple.reminderkit`) — ReminderKit's connection to its daemon being recycled; EventKit re-establishes it automatically.

**Filter in Console.app:** exclude subsystem `com.apple.BackgroundSystemTasks`.
**Noisy Xcode debug runs:** set `OS_ACTIVITY_MODE=disable` in the scheme's environment variables.

## Rules (moved from CLAUDE.md, 2026-10-04)

Moved verbatim from `Cosmic Daybook/CLAUDE.md` on 2026-10-04 so that file keeps only a pointer and the few rules a session needs before touching this area. These are still rules: follow them.

The full notes (history, recovery, the beta-SDK warnings and console noise to ignore) are in `docs/Technical notes/CloudKit/CLOUDKIT_GUIDE.md`, under "Working notes from CLAUDE.md". The rules every change must keep:

- **Environments:** `CLOUDKIT_ENVIRONMENT` (project-level, `Production`) picks the environment for both apps; change it only in the project. A new key describing one store's sync state goes through `CloudKitEnvironment.scoped`.
- **Container:** reach it through `CloudKitConfigurationService.container`, never `CKContainer.default()` (the Daybook Assistant has its own bundle ID but shares the container).
- Two stores, private and shared; schema changes are additive-only after deployment; foreign keys are strings.
- **The classroom share** holds only `CoreDataStack.sharedEntityNames`. It is created once, by Settings → Classroom → Set Up Classroom Sharing; `classroomShare(among:in:)` returns the pinned share, never `.first`. **Never move already-shared records with `container.share(_:to:)`** (on 2026-09-27 that killed export for the session), and **never take a record out of the share** except through `ClassroomShareRelease`.
- New share-type records join the share through `SharedStoreOrphanGuard` (notebook) and `AssistantShareAttacher` (Assistant); nothing attaches during a first download (`FirstDownloadGate`). Don't add sweeps that attach records that merely *look* unshared.
- **Attendance writes go through `CDAttendanceStore`** (marks, notes, pickups, Back in Class, permissions); day locks through `AttendanceDayLocks`; the front-desk email log through `AttendanceEmailLog`.
- **A screen built from a one-off fetch must listen for imports:** `onPresentationDataChange(WhenVisible)`, adding the entity to `PersistentHistoryProcessor.presentationEntityNames` if it isn't there.
- **Persistent history:** purge only what predates both the last export's start and 180 days; only the primary on-disk stack creates a `PersistentHistoryProcessor`; positions are per store, so never save a coordinator token or another store's token as a store's position.
- **Schema:** after a model change, one Debug Development run with `-InitializeCloudKitSchema`, verify in CloudKit Console, deploy to Production before release.
- **iCloud Drive files** (managed PDF folders, backups, note photos) go through `UbiquitousFile`: on iOS another device's file is a placeholder until downloaded, and writes are coordinated. Never orphan-clean the iCloud photo folder.
- **Account status:** `CKContainer.accountStatus` / `.CKAccountChanged` for sync health, never `ubiquityIdentityToken` (that is iCloud Drive).
- **Save observers:** typed `.didSave` messages, not `.didSaveObjectIDs(Async)` (they double-fire on the 27.0 SDK). Files the Daybook Assistant compiles stay on classic notifications (iOS 18 target).
