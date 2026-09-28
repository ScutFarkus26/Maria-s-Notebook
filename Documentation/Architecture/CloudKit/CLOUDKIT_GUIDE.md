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

**Entity routing** (`CoreDataStack+Model.swift`):
- The classroom entities (students, attendance, the school calendar, and so on) belong to both configurations.
- Teacher-only entities belong to Private only.
- New records land in the first store added, which is the private one. The lead guide wants that.
- The assistant doesn't, so `CDAttendanceStore` assigns her records to the shared store explicitly.

**Store options** (`CoreDataStack+Stores.swift`): history tracking and remote-change notifications are on for every store, along with automatic lightweight migration.

**If loading fails**, `AppBootstrapping+CloudKit.swift` falls back in order:
1. The CloudKit stack.
2. The same files without CloudKit.
3. A unified local store.
4. In-memory.

**Schema initialization:** `initializeCloudKitSchema` runs only in DEBUG with
`-InitializeCloudKitSchema`. Deploy the development schema to production in the
CloudKit Console before shipping a model change. A monotonic
`currentSchemaVersion` guard (`CoreDataStack+SchemaVersion.swift`) stops an
older build from migrating a newer store backwards.

## 2. Sharing: one classroom, one share

- **Creating the share.** The lead guide's classroom is a Core Data–managed
  per-zone share (`com.apple.coredata.cloudkit.share.*`), created with
  `container.share(_:to: nil)` on a background context
  (`SharedStoreZoneRepair+Sharing.swift`,
  `ClassroomSharingService+AutoCreate.swift`). Before creating one, the app
  checks the local shares, the membership row's zone, and the server's zone
  list, so it never mints a duplicate zone.
- **Choosing the share.** A store can hold several shares, and
  `fetchShares(in:)` has no order. `CDClassroomMembership.classroomShare(among:in:)`
  picks the one whose zone the membership row names. Never take `.first`.
- **Inviting (Mac).** `ClassroomMembersSheet` is the Mac's own members sheet.
  It looks the person up with `shareParticipants(for:)`, adds them, and saves
  with `persistUpdatedShare(_:in:)`.
  - Adding someone already on the share is refused locally.
  - The server's `participantAlreadyInvited` (iOS/macOS 26) becomes "already invited".
  - "Remove Everyone" removes participants but keeps the share, because the
    share is what keeps the lead guide's records syncing.
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
- **Accepting.** `acceptShareInvitations(from:into: sharedStore)`, then an
  assistant membership row is written.
  - iOS: the scene delegate (`ShareAcceptanceAppDelegate`).
  - macOS: `application(_:userDidAcceptCloudKitShareWith:)`.
  - Invitations that arrive before the service exists wait in `ShareInvitationInbox`.
- **Leaving.** `purgeObjectsAndRecordsInZone(with:in:)`.

**Never move a record that's already in one share into another** with
`share(_:to:)`. On 2026-09-27 that failed with 134410 → 134421 and killed the
mirroring delegate for the session. Attaching orphans (records in no share)
is the only move that works.

## 3. The Daybook Assistant

An iOS-only companion (`Daybook Assistant/`, deployment target iOS 18.0). It
compiles about 40 of the main app's files by path and builds the same
`CoreDataStack` and `ClassroomSharingService`.

- **What it touches.** It reads students, attendance (with notes) and the
  school calendar, and writes today's attendance only.
- **What it skips.** It runs no history processor and no zone repair (`#if !ASSISTANT_APP`).
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
- **Settings → Classroom**: role, members, the invite sheet, and Repair Sync Errors.
- **Settings → Classroom → Sync Diagnostics.**
- **Settings → Database → Maintenance**: Reset Local Cache and Re-sync from iCloud.
- **The MCP `sync_status` tool**: the same state as the service.

Two numbers are not what they sound like:
- **"Sync Now"** only saves the view context.
- **"Pending changes"** counts local saves since the last event, not records waiting to upload.

## 6. Shared-store zone repair

Records that should be in the classroom share but sit in no share poison the
mirroring delegate (`NSCocoaErrorDomain 134060`). `SharedStoreZoneRepair`
finds them in the *private* store and attaches them with `share(_:to:)` in
chunks of 200.

**When it runs:**
- after launch,
- when sharing turns on,
- after each dedup pass,
- from `SharedStoreOrphanGuard` whenever the view context inserts a classroom entity.

**What stops it:**
- A 24-hour circuit breaker on 134060.
- A per-session stop once the mirroring delegate dies.
- `EnergyPolicy` deferral.
- `FirstDownloadGate`: nothing runs until the first import after a reset
  finishes, because mid-download rows arrive before their CKShare and look
  like orphans.

## 7. iCloud Drive and key-value storage

**Files.** PDFs, backups and note photos live in the ubiquity container. Go
through `UbiquitousFile`:
- a placeholder counts as present,
- reads download first,
- writes, moves and deletes are coordinated.

**Preferences.** `SyncedPreferencesStore` (see
[KEY_VALUE_STORAGE_IMPLEMENTATION.md](../../Implementation/KEY_VALUE_STORAGE_IMPLEMENTATION.md)).

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
   - A new share zone appearing unexpectedly means something created a duplicate share.
6. **Apple's references:**
   - [TN3163: Understanding the synchronization of NSPersistentCloudKitContainer](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer)
   - TN3164 (debugging the container)
   - TN3162 (CloudKit throttles)

**Last resort.** Settings → Database → Maintenance → Reset Local Cache. The
first download afterwards is gated (see §6). Don't repair or seed during it.

---

## Related Documentation

- `Cosmic Daybook/CLAUDE.md`, CloudKit Notes: the rules in brief
- [KEY_VALUE_STORAGE_IMPLEMENTATION.md](../../Implementation/KEY_VALUE_STORAGE_IMPLEMENTATION.md): iCloud KVS preference sync
- [ARCHITECTURE.md](../ARCHITECTURE.md): architecture guide
