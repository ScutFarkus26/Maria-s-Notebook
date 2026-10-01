# CloudKit Guide

How Cosmic Daybook and the Daybook Assistant sync through CloudKit, how to tell
whether sync is healthy, and the rules that keep it that way.

**Last Updated**: September 28, 2026 (iOS/macOS 27 SDK; main app targets 27.0, Daybook Assistant 18.0)

The short rules live in `Cosmic Daybook/CLAUDE.md` → CloudKit Notes. This
document explains the design behind them.

## 1. The stack

Sync is `NSPersistentCloudKitContainer` end to end
(`AppCore/CoreDataStack.swift`). There is no `CKSyncEngine`, no SwiftData and
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
reads (`AppCore/CloudKitEnvironment.swift`). Development-signed builds obey it;
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
- **Invite preflight.** Manage Sharing (Mac members sheet and iOS
  `UICloudSharingController`) goes through `shareForInvitations`, which refuses
  unless the pinned share exists and holds students, and shows what it holds.
- **Inviting (Mac).** `ClassroomMembersSheet` is the Mac's own members sheet.
  It looks the person up with `shareParticipants(for:)`, adds them, and saves
  with `persistUpdatedShare(_:in:)`.
  - Adding someone already on the share is refused locally.
  - The server's `participantAlreadyInvited` (iOS/macOS 26) becomes "already invited".
  - "Remove Everyone" removes participants but keeps the share: a new one
    would be a second zone.
- **Inviting (iOS).** `UICloudSharingController`.
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
[KEY_VALUE_STORAGE_IMPLEMENTATION.md](../../Implementation/Archive/KEY_VALUE_STORAGE_IMPLEMENTATION.md)).

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
- [KEY_VALUE_STORAGE_IMPLEMENTATION.md](../../Implementation/Archive/KEY_VALUE_STORAGE_IMPLEMENTATION.md): iCloud KVS preference sync
- [ARCHITECTURE.md](../ARCHITECTURE.md): architecture guide
