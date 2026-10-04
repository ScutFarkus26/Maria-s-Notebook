# Backup & Restore System

**Last Updated:** 2026-09-28

> Authoritative summary lives in `Cosmic Daybook/CLAUDE.md` ("Backup System").
> This file is the longer-form companion. If they disagree, CLAUDE.md wins.

## Overview

Backups are **encrypted Apple Archives** (format v19): one LZFSE-compressed,
AES-CTR+HMAC-encrypted container per backup, holding a manifest plus newline-
delimited JSON (NDJSON) for each Core Data entity type. The system does
streaming export with read-back verification, transactional restore with
checkpoint rollback, change-gated automatic backups, and CloudKit-aware
delete/sync handling.

This replaced an earlier design (AES-GCM envelope + Ed25519 signing + manual
SHA256, the `BackupCodec`/`StreamingBackupWriter`/`SelectiveExportService`
family). Those files no longer exist; encryption, compression, and integrity
now come from the AppleArchive/AEA layer plus a post-write structural check.

---

## Architecture

### Archive implementation (current code path)

| File | Purpose |
|------|---------|
| `Backup/Archive/BackupCoordinator.swift` | The single app-facing API. UI calls `exportBackup`, `previewImport`, `importBackup`, `verifyBackup`. |
| `Backup/Archive/BackupArchive.swift` | Low-level AppleArchive wrapper. Encrypted write (`AA01`), read of both encrypted v19 and plain v17/v18 (`pbz*`), magic-byte detection, per-entry size guard. |
| `Backup/Archive/BackupEncryptionKeyStore.swift` | The 256-bit symmetric key in the iCloud Keychain (synchronizable, after-first-unlock). `fetchOrCreateKey()` for export, `requireKey()` for restore. |
| `Backup/Archive/BackupWriter.swift` | Builds a v19 backup: collect payload (main actor) → serialize NDJSON + manifest → write encrypted temp file → verify → atomic rename (all off-main). Aborts on any entity encode failure. |
| `Backup/Archive/BackupWriter+Streaming.swift` | The export as it normally runs (2026-09-26): one entity type at a time — collect on the main actor, encode NDJSON and pack it (LZ4) off it — then key, manifest, preferences and the entries unpacked one by one into the archive. Same entries, order and bytes as the one-pass export. |
| `Backup/Archive/BackupSnapshotWatch.swift` | Keeps a streamed export one moment: asked after every type (a change flag on the view context's coordinator) and at the end (persistent history). Any change, or unsaved edits at the start, sends the export to the one-pass path. |
| `Backup/Archive/BackupReader.swift` | Decodes an archive into manifest + entries + preferences. `verifyStructure` streams the archive counting rows without holding the payload. |
| `Backup/Archive/BackupImporter.swift` | `restore(from:into:…)`, the app's restore and the checkpoint rollback's: `decodeArchive` (off-main, `@concurrent`) decodes each entry as it is read into one `BackupPayload`, then `BackupService.importRows` imports it one entity type at a time from a `BackupPayloadSource` holding its only copy. Surfaces decode skips and unknown entities as warnings, in archive order. `decodePreview` (`+Preview`) streams the entries for the restore preview and keeps only row counts and IDs (`BackupPreviewDigest`). |
| `Backup/BackupRestoreRun.swift` (+ `+CoreTypes`, `+PlanningTypes`, `+LaterTypes`) | One restore in progress: the context, the `BackupEntityIndex`, the source, and the restore order — the importer calls, parents first — each asking for its type by payload field (`rows(\.students)`). `BackupPayloadSource` hands each type over once, moved out of the payload and deduplicated in place (`BackupEntity.take`), so the payload shrinks as the import goes. Keeps notes' link ids (`BackupNoteLinks`) for the end-of-restore relink and the album ids for the reattach warning. |

### Shared services (reused by the archive implementation)

| File | Purpose |
|------|---------|
| `Backup/BackupService+DataCollection.swift` | `collectPayload` — the one-pass collect: every entity type in one main-actor turn, through the collector table in `+EntityCollectors` (fetched in batches, run through the DTO transformers). The streamed export walks the same table one type at a time. `fetchAndTransformInBatches` reads each type from the store 1,000 rows a page (`includesPendingChanges = false`), leaves out rows the context has deleted, adds its unsaved inserts once at the end, and ends a type on a short page of *rows*, never of DTOs, since the transformers skip malformed rows (2026-09-26; before that, unsaved edits in a type past one page duplicated or dropped rows, and one malformed row on a full page cut the rest of its type). An in-memory store is read in one fetch (2026-09-27): it gets an unsorted fetch's offset and limit wrong, and a type of 1,205 notes was backed up as 1,001. |
| `Backup/BackupService+Restoration.swift` | `importRows` — saves edits made before the restore, then the replace-mode clear, the ordered import (`BackupRestoreRun`), note relink, save and denormalized-field repair (anything left unsaved discarded if one fails), preferences, CloudKit export wait. `importPayload` restores a whole payload through it (tests that build payloads by hand). |
| `Backup/BackupFetchHelper.swift` | `BackupEntityIndex` (restore: one lazy fetch per type) and `EntityIDIndexCache` (preview: one id-set fetch per type). Replaced the old per-record fetch. |
| `Backup/Core/BackupEntityRegistry.swift` | Single source of truth for which entity types are backed up. |
| `Backup/Core/BackupChangeTracker.swift` | Persistent-history gate: skips an automatic backup when nothing changed since the last one. |
| `Backup/Services/BackupTransactionManager.swift` | `executeWithRollback` — safety checkpoint before destructive restore, auto-rollback on failure. |
| `Backup/BackupVerification.swift` | User-facing verify: streams the archive, checks manifest counts vs. actual rows, reports encryption. |
| `Backup/Core/AutoBackupManager.swift` | Scheduled / quit / background / pre-destructive backups, retention cleanup. |

### Lifecycle entry points

| File | Trigger |
|------|---------|
| `AppCore/AutoBackupAppDelegate.swift` | macOS quit — `applicationShouldTerminate` returns `.terminateLater`, backup runs async, then replies. |
| `AppCore/BackupBackgroundTaskManager.swift` | iOS — `BGProcessingTask` registration + scheduling (requires external power; an expired run stops between entity types and leaves no file). |
| `AppCore/CosmicDaybookApp+Startup.swift` | iOS scene-phase `.background` trigger (under a `UIApplication` background-task assertion, at `.utility`). |
| `AppCore/AppServicesLauncher.swift` | Starts the interval schedule once per process (`AutoBackupManager.startScheduledBackups`): a loop on iOS, `NSBackgroundActivityScheduler` on macOS (`Backup/Core/ScheduledBackupActivity.swift`). |

---

## Format Versions

| Version | Container | Notes |
|---------|-----------|-------|
| v5–v16 | JSON envelope + LZFSE (+ SHA256 / AES-GCM in some) | **No longer readable by the app.** Recover via the external Python/`aa` recipe. |
| v17 | Plain LZFSE Apple Archive (`pbz*`) | First NDJSON-in-archive format. Read-only now. |
| v18 | Plain LZFSE Apple Archive (`pbz*`) | Adds DayPad, YearPlanEntry, LessonSequenceSettings, Story, BookClub entries. Read-only now. |
| v19 | Encrypted Apple Archive (`AEA1`) | AES-CTR + HMAC, key from iCloud Keychain. Same entry layout as v18. |
| v20–v22 | Encrypted Apple Archive (`AEA1`) | Additive entries: Guardians + Parent Communications (v20), teaching-album annotations (v21), lesson↔album links (v22). |
| v23 | Encrypted Apple Archive (`AEA1`) | `preferences.json` grows to the full user-settings set (school year, recall, AI models, view state, per-date attendance locks, album folder bookmarks + fingerprints) and gains a `plist` value type. Entity entries unchanged. |
| v24 | Encrypted Apple Archive (`AEA1`) | `ScheduledMeeting` entries carry `purpose`. Additive. |
| v25 | Encrypted Apple Archive (`AEA1`) | `Lesson` entries carry `isKeyLesson` (the Three-Year View's milestone flag), and `preferences.json` carries the view's untouched-area thresholds, zoom and granularity. Additive. |
| v26 | Encrypted Apple Archive (`AEA1`) | `WorkModel.statusRaw` may carry the merged status vocabulary. Entry layout unchanged. |
| v27 | Encrypted Apple Archive (`AEA1`) | Adds `OrderItem` entries and the `Orders.*` preferences. Additive. |
| v28 | Encrypted Apple Archive (`AEA1`) | Note photos follow the entity entries as `photos/<filename>` (the photo file's bytes), counted in the manifest's optional `photoCount` and checked by read-back verification (`BackupPhotos`). On by default (`Backup.includesNotePhotos`); never in the pre-restore checkpoint; a photo not on the device is left out. Restore stages them and installs after the records import, never over an existing file. Entity entries are byte-identical to v27; a v27 reader rejects the new paths. |
| v29 | Encrypted Apple Archive (`AEA1`) | `AttendanceRecord` entries carry `note` (schema 8). Additive. |
| v30 | Encrypted Apple Archive (`AEA1`) | Schema 9: `AttendanceDayLock` entries (a model-driven row: id, date, lockedAt, lockedByID), the locked attendance days that used to travel only as `Attendance.locked.<date>` preferences. `StudentTrackEnrollment` entries no longer re-link a `student` relationship (it was removed; `studentID` is the link). Entry labels follow schema 9's routing: only the five classroom-share types are `shared/`; the 28 types that left the share are `private/`. |
| **v31** | **Encrypted Apple Archive (`AEA1`)** | **Current write format.** Adds `SupplyTransaction` entries (a model-driven row: id, supplyID, date, quantityChange, reason), each supply's stock history; restore re-links `supply` from `supplyID`. Earlier formats left the type out, so restoring one keeps supply quantities but no history. Additive. |

`BackupReader.supportedFormatVersions = 17...31`.

---

## Archive Layout

```
[AEA1 — Apple Encrypted Archive, AES-CTR+HMAC, LZFSE inside]
  manifest.json            ← format version, entity counts, origin-store routing, app/device metadata
  preferences.json         ← typed preferences dictionary
  private/Note.ndjson       ← one JSON DTO per line
  private/AttendanceRecord.ndjson
  shared/Student.ndjson
  shared/Lesson.ndjson
  …
```

Each entity entry is named `<store>/<EntityName>.ndjson`, where `<store>` is
`private` or `shared`, mirroring `CoreDataStack.sharedEntityNames` so the
importer routes each type to the correct persistent store on restore.

---

## Export Flow

1. `BackupCoordinator.exportBackup` → `BackupWriter.write` (main actor).
2. **Streamed (the normal path, 2026-09-26):** for each entity type in archive order, collect its DTOs on the main actor (view-context queue), then encode its NDJSON and pack it with LZ4 off the main actor, so only one type's DTOs and NDJSON are alive at a time (export peak 53.8 → 38.2 MB on a 44,318-row store). The manifest has to be the first entry and needs every count, so the packed entries wait until the last type is collected. `BackupSnapshotWatch` is asked after every type and once at the end; if anything could have changed a fetch in between (an edit, a save on the coordinator including a CloudKit import, a reset, a history transaction), the streamed rows are dropped and the one-pass path runs instead.
   **One pass (fallback):** when the view context holds unsaved edits at the start, or the watch saw a change, `collectPayload` fetches every type as DTOs in one main-actor turn, as the export always did before.
3. Off the main actor: serialize NDJSON + manifest (one pass) or unpack each staged entry in turn (streamed), fetch/create the Keychain key.
4. Write the encrypted archive to a hidden `.partial` temp file in the destination directory (`0600`).
5. **Verify:** re-read via `BackupReader.verifyStructure` — manifest must round-trip and every entity's NDJSON row count must match the manifest.
6. Atomically rename the temp file into place. On any failure the temp file is removed and nothing lands at the destination.

Any single entity type failing to encode aborts the entire export — a backup
silently missing data is worse than a failed one.

---

## Restore Flow

**`ClassroomMembership` is carried but never restored** (`BackupEntityRegistry.keptOnRestoreEntityNames`,
2026-09-28). Its rows pin a CloudKit share zone, and a zone exists only in the environment and notebook
that made it: restoring the Development backup into the Production notebook must not pin a Development
zone, and a Replace restore must not make the device forget the share it has. Restore neither clears nor
writes those rows; the type is still asked for in order (and freed) like every other.

1. `BackupCoordinator.importBackup` → `BackupTransactionManager.executeWithRollback`.
2. For `.replace`, a safety checkpoint (current-format backup) is written first; if it fails, the restore aborts before deleting anything.
3. `BackupImporter.restore` → `decodeArchive` (off-main, `@concurrent`) reads and decrypts the archive and decodes each entry as it is read, in archive order, into one `BackupPayload` — the same payload and warnings as decoding after the whole read, with no entry's NDJSON outliving its decode. It fails exactly as the reader does (bad entry path, missing manifest, unsupported version).
4. The payload is handed whole to a `BackupPayloadSource`, which then holds its only copy, and `BackupService.importRows` (main actor, **one turn from the pre-save to the CloudKit wait** — nothing in it suspends):
   - saves any edits the view context already held (the restore's final save would commit them anyway, as it always has), so that a failure can discard exactly the restore's own changes; if they can't be saved, the restore doesn't start and they stay unsaved,
   - for `.replace`: context-level delete of every backed-up type except `ClassroomMembership` (emits CloudKit tombstones — never `NSBatchDeleteRequest`),
   - imports every type in dependency order through `BackupRestoreRun`. When a type's turn comes it is moved out of the payload and deduplicated in place (first row of each id, within the type — the deduplication never worked across types), imported, and freed, so the records never exist twice and shrink as the import goes (the one-pass restore deduplicated into a second full copy and kept both until the end). The restore order is not the archive's: CommunityTopic before LessonAssignment and Note, ProjectRole before ProjectSession. `BackupEntityIndex` is built lazily per type, so a type sees the parents imported before it in this restore. **Merge mode updates in place:** each importer resolves the pre-restore record for the DTO's ID (`ExistingLookup`) and populates it; the backup wins for any ID it holds, records absent from the backup are kept. Replace mode has already cleared the store, so the same path inserts everything,
   - relinks notes to the records they point at, from the ids kept while notes were imported (`BackupNoteLinks`; the notes' rows are freed by then),
   - `save()`, then repairs denormalized fields. If anything from the clear through the repair fails, everything the restore left unsaved is discarded (`viewContext.rollback()`): in that one turn nothing else can have changed the context, so a failed merge restore no longer leaves half a restore for the next save anywhere to commit, and the guide's edits, saved first, are kept,
   - applies preferences (`BackupPreferencesService`; album folder bookmarks union with the local list, the album fingerprint map merges local-wins), then turns any `Attendance.locked.<date>` preference the backup carried into an `AttendanceDayLock` record (a backup from before v30),
   - reloads the album library if it was already open, and warns when the backup holds album annotations but no album folder resolves on this device.

   The one turn is deliberate. Between two types, other main-actor work could run against a half-restored store: the quit-time backup would export it and let the app quit before the save (after replace mode's clear was already saved), a scheduled or background backup would write it, an MCP write could save or roll back the restore's pending changes, and `isRestoring` would swap Settings — with this restore's progress and summary — out of the window. Decoding stays off the main actor, before the turn. On a 44,318-row store (2026-09-27, iOS simulator on an M-series Mac, medians of six) the restore's peak heap fell from 54.4 MB to 28.2 MB with the import turn within the run-to-run spread of the old one (868 → 947 ms in one run, 1,002 → 1,057 ms in another). A version that decoded each type inside the turn peaked at 33.2 MB but nearly doubled the turn (1.88 s); decoding a type across cores was slower than one line at a time. `BackupRestorePeakMemoryTests` (on request) measures the old restore against the app's.
5. The CloudKit export wait is subscribed **before** `save()` so a fast export isn't missed; it blocks up to 30 s, then reports "still syncing in background."
6. The summary's warnings are the restore's own (album, iCloud), then the entries left out — rows that did not decode, entities this version does not know — in archive order, as before.
7. On any import failure, the transaction manager rolls back to the checkpoint (`.replace`); a merge restore has no checkpoint, and has already discarded its own unsaved changes.

---

## Encryption & Key Management

- AES-CTR + HMAC via `ArchiveEncryptionContext` (profile `hkdf_sha256_aesctr_hmac__symmetric__none`).
- 256-bit `SymmetricKey` in the **iCloud Keychain** — synchronizable so a backup made on one device restores on another signed into the same Apple ID (the lost-device case backups exist for). `kSecAttrAccessibleAfterFirstUnlock` lets scheduled/background backups run while locked.
- Files are `0600`.
- Restore on a device whose Keychain hasn't synced the key yet fails with an actionable message rather than deep inside stream setup.

---

## Automatic Backups

- **Triggers:** macOS quit, iOS background (scene phase + `BGProcessingTask`), the interval schedule (iOS loop; macOS `NSBackgroundActivityScheduler` with 10% tolerance at `.utility`), pre-destructive.
- **Change-gated:** `BackupChangeTracker` records the persistent-history token after each auto-backup and skips the next one if no transactions occurred since. Fail-open — any uncertainty performs the backup.
- **Retention:** keeps the newest N (default 10) of `AutoBackup-`/`ScheduledBackup-`/`PreOp-` files.

---

## Entity Coverage (test-enforced)

`BackupCoverageTests` keeps three lists in lockstep and guards against
forgetting a new entity:

- `BackupEntityRegistry.allTypes` (what replace-mode clears)
- `BackupWriter.serializedEntityNames` (what export writes)
- `BackupImporter.handledEntityNames` (what import reads)

plus: every entity in the managed object model must be either in the registry
or in an explicit exclusion list (the 8 removed-feature tombstones —
`WorkCycle*`, `PrepChecklist*`, `TransitionPlan*`, `Initiative`). Adding an
entity without backup coverage turns a test red.

### Adding a new entity type

1. Add the `CDType` to `BackupEntityRegistry.allTypes`.
2. Add a DTO + transformer (`Backup/Export/BackupDTOTransformers*.swift`) and a field on `BackupPayload`.
3. Add a row to `BackupWriter.entitySerializations`.
4. Add a decoder to `BackupImporter.entityDecoders` and an importer call in the restore order (`BackupRestoreRun+CoreTypes` / `+PlanningTypes` / `+LaterTypes`, after the types it links to), reading its rows with `rows(\.field)`.
5. Bump `BackupWriter.formatVersion` and extend `BackupReader.supportedFormatVersions` if the addition is structural.

---

## Not Implemented

- **Incremental/delta backups** — `BackupChangeTracker` already provides the persistent-history plumbing; deltas would build on it.
- **Legacy (v5–v16) import** — intentionally removed; external recovery only.
- **Document/attachment payloads** — backups carry metadata, not imported files (by design; surfaced as an export warning).

---

## Testing

- `Cosmic Daybook Tests/Backup/BackupRoundTripTests.swift` — end-to-end round trips, encryption/verification, merge mode, corruption rejection, v18 entity fidelity.
- `Cosmic Daybook Tests/Backup/BackupCoverageTests.swift` — coverage exhaustiveness (registry ≡ writer ≡ importer ≡ model − exclusions).
- `Cosmic Daybook Tests/Backup/BackupCheckpointSafetyTests.swift` — checkpoint failure aborts before any destructive delete.
- `Cosmic Daybook Tests/Backup/BackupRestoreEquivalenceTests.swift` — the restore against the old one-pass restore (kept verbatim in `BackupService+LegacyRestore.swift`): the same records, summary, progress and re-export in merge and replace modes, with and without the guide's unsaved edits pending; children ahead of parents in the archive; undecodable rows, entries written twice and unknown entities.
- `Cosmic Daybook Tests/Backup/BackupRestoreTransactionTests.swift` — the old errors for broken archives; a replace restore failing part-way rolls back to its checkpoint; a merge restore failing part-way discards exactly its own changes and keeps the guide's; every type asked for once, in order; decode off the main thread and one main-actor turn from the clear to the save.
- `Cosmic Daybook Tests/Backup/BackupRestorePeakMemoryTests.swift` — on request (`TEST_RUNNER_BACKUP_PEAK_MEMORY=1`): peak heap and main-thread import time, the old one-pass restore vs the app's.

```bash
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  xcodebuild test -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" \
    -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
    -only-testing:"Cosmic Daybook Tests/BackupRoundTripTests" \
    -only-testing:"Cosmic Daybook Tests/BackupCoverageTests" \
    -only-testing:"Cosmic Daybook Tests/BackupCheckpointSafetyTests"
```


## Working notes from CLAUDE.md

Moved verbatim from `Cosmic Daybook/CLAUDE.md` on 2026-10-02 so that file keeps only the rules every session needs. Dates in the notes are when each change landed.

### Backup System

- **Current write format: v37 (encrypted Apple Archive)**; v37 adds Restock (schema 15): supply entries carry `levelRaw`, `sourceRaw`, `urlString`, `levelChangedAt` / `levelChangedByID` / `levelChangedByName` and the dormant `minimumThreshold` and `unit`, order items `sourceRaw`, `supplyID`, `addedByID` / `addedByName`, and the three Restock types are written under `shared/` (restore matches the entity name, so older `private/` entries still restore; an older backup's order items read as orders, its staples get levels from their counts after the restore); v36 adds `returnedAt` and `statusBeforeLeavingRaw` to attendance entries (schema 14); v35 adds `leavesAt` to attendance entries (schema 13); v34 adds `AttendanceEmailSend` / `AttendanceEmailSettings` entries (schema 12); v33 `leftAt` and v32 `markedAt` on attendance entries; v31 added `SupplyTransaction` entries (stock history, re-linked to its supply by `supplyID`; earlier backups left it out); v30 added `AttendanceDayLock` entries (schema 9) and drops the enrollment → student re-link; v29 added `note` to attendance entries (schema 8). Files are genuine Apple Encrypted Archives — first 4 bytes are `AEA1`, AES-CTR + HMAC via `ArchiveEncryptionContext` (profile `hkdf_sha256_aesctr_hmac__symmetric__none`), with LZFSE compression inside the AEA layer. The 256-bit symmetric key lives in the **iCloud Keychain** (`Backup/Archive/BackupEncryptionKeyStore.swift`, `kSecAttrSynchronizable` + `kSecAttrAccessibleAfterFirstUnlock`) so a backup written on one device restores on any device on the same Apple ID. Files are written `0600`. Contents: a `manifest.json` first entry (format version + entity counts + origin-store routing), `preferences.json`, then one NDJSON entry per Core Data entity type, prefixed `private/` or `shared/` to indicate origin store, then (v28+) one `photos/<filename>` entry per note photo on the device (`Backup/Archive/BackupPhotos.swift`; the manifest's `photoCount`, checked by read-back verification). Photos are on by default (`Backup.includesNotePhotos`, Settings › Data › Auto-Backup card); the pre-restore checkpoint never carries them; a photo still downloading from iCloud is left out rather than waited for. Restore stages photos in a temp folder during decode and installs them only after `importRows` succeeds, never over an existing file of the same name. A v27 reader rejects `photos/` paths, which is why this is a version bump; entity entries are byte-identical to v27, so the golden/sparse references (still named `-v27`) did not change.
- **Read support: v17–v37** (`BackupReader.supportedFormatVersions`). v19+ is the encrypted container; v17/v18 are plain LZFSE Apple Archives (magic `pbz*`) and still read so older backups and checkpoints restore. `BackupArchive.isBackupArchive(at:)` accepts both magics; `isEncryptedArchive(at:)` distinguishes them. **Legacy v5–v16 JSON-envelope `.mtbbackup` files cannot be read by the app at all** — that decoder was removed; use the external recovery process referenced in `Documentation/Architecture/BACKUP_SYSTEM.md`. The repo's own `Backups/*.mtbbackup` through 2026-04-01 are all this unreadable legacy format.
- Top-level entry point: `Backup/Archive/BackupCoordinator.swift`. UI calls `coordinator.exportBackup`, `coordinator.previewImport`, `coordinator.importBackup`.
- **Threading:** payload collection runs on the main actor (Core Data view-context queue); NDJSON encode, encryption, archive write, read-back verification, and decode all run off the main actor (`BackupWriter.encodeAndWrite`, `BackupImporter.decodeArchive` are `@concurrent`; plain `nonisolated async` would run on the caller's actor under this project's settings).
- **The export streams (2026-09-26):** `BackupWriter+Streaming` collects one entity type on the main actor, encodes and LZ4-packs it off the main actor (`stage` / `writeStaged`, `@concurrent`), then moves to the next, so only one type's DTOs are alive at a time; the archive is byte-for-byte the one-pass export's. Other main-actor work runs between types, so `BackupSnapshotWatch` is asked after each type and at the end (persistent history); on any change, or unsaved view-context edits at the start, the streamed rows are dropped and the one-pass `collectPayload` runs. The watch listens to its own coordinator only — never the process-wide `.presentationDataDidChange`. Restore preview streams too: `BackupImporter.decodePreview` keeps only row counts and IDs (`BackupPreviewDigest`).
- **Integrity:** export writes to a hidden temp file in the destination dir, re-reads it (`BackupReader.verifyStructure` — streams the whole archive, checks the manifest decodes and per-entity NDJSON row counts match), then atomically renames into place. An encode failure for any entity type aborts the whole export (`BackupWriter.WriterError`) rather than silently dropping data; a malformed entry on read surfaces as a warning in `BackupOperationSummary`.
- Auto-backup on macOS quit (`applicationShouldTerminate` → `.terminateLater`), on iOS scene-phase `.background` + a `BGProcessingTask` (`AppCore/BackupBackgroundTaskManager.swift`, id `DanielSDeBerry.MariasNoteBook.backup`; requires external power and stops between entity types when iPadOS expires it), plus a configurable interval schedule (a loop on iOS; `NSBackgroundActivityScheduler` on macOS, `Backup/Core/ScheduledBackupActivity.swift`); retention default 10. All automatic triggers are **change-gated** via persistent history (`Backup/Core/BackupChangeTracker.swift`) — an untouched dataset skips the backup. Honors the user's chosen destination folder.
- Restore goes through `BackupTransactionManager.executeWithRollback` (safety checkpoint + auto-rollback on failure). Checkpoints are written in the current format via `BackupWriter`.
- **Restore holds the backup once (2026-09-27):** the archive is decoded off the main actor, and `BackupService.importRows` imports from that payload's only copy, type by type in dependency order (`BackupRestoreRun+CoreTypes` / `+PlanningTypes` / `+LaterTypes`), deduplicating each type in place and freeing it once imported — peak 54.4 → 28.2 MB on a 44,318-row store, main-thread import time about the same. Everything from the replace-mode clear to `viewContext.save()` is one main-actor turn: **nothing in it may `await`** (between types, the quit backup would export a half-restored store, an MCP write could save or roll back its pending changes, and Settings would swap out mid-restore). Edits the view context held before the restore are saved first; a failure before the restore's own save discards only the restore's changes (a failed merge used to leave half a restore pending for the next save anywhere). `importPayload` restores a hand-built payload through the same path (tests). `BackupRestoreEquivalenceTests` / `BackupRestoreTransactionTests` pin it against the old restore kept verbatim.
- Restore upsert/relationship lookups use `BackupEntityIndex` (one fetch per entity type, built lazily so child types see parents inserted earlier in the same restore) — not a fetch-request-per-record. Preview checks the digest's IDs with `EntityIDIndexCache` (one id-set fetch per type).
- **Merge mode is an upsert, not insert-only:** every importer resolves the pre-restore record for the DTO's ID via `ExistingLookup` and populates it in place (backup wins for any ID it holds); records absent from the backup are left alone. Replace mode clears the store first, so the same code path inserts everything. Never delete-and-reinsert an existing row — that nullifies relationships from records the backup doesn't know about and emits CloudKit tombstones.
- **Preferences entry (v23+):** `Backup/Core/BackupPreferencesService.swift` lists every user-chosen setting that is backed up (school year, recall spacing, the Private Cloud permission, view state, per-date attendance locks via `preferenceKeyPrefixes`, album folder bookmarks + fingerprint map). Device-only plumbing (CloudKit tokens, window positions, the MCP toggle, migration flags) is deliberately excluded. List/map values ride in `PreferenceValueDTO.plist`. Album keys use a merge policy on restore (bookmarks union, fingerprints local-wins) so a merge never drops a folder the device already registered.
- **Album annotations after restore:** bookmarks/notes/highlights/ink key on the album PDF filename. If no album folder bookmark resolves on the restoring device, `importRows` adds a warning telling the guide to add the folder; once they do, `AlbumIdentityRepair` uses the restored fingerprint map to reattach annotations even when the PDFs came back under new filenames.
- The post-restore CloudKit export wait subscribes to `NSPersistentCloudKitContainer.eventChangedNotification` **before** `viewContext.save()` so a fast export isn't missed (`BackupService+Restoration.swift`).
- `replace` mode uses context-level deletes (NOT `NSBatchDeleteRequest`) so CloudKit mirroring sees proper delete tombstones.
- **`ClassroomMembership` is carried but never restored** (`BackupEntityRegistry.keptOnRestoreEntityNames`): its rows pin a share zone that exists only in the environment that wrote them, so restore neither clears nor writes them — a Replace restore keeps this device's pin, and the Development backup restored into Production pins nothing.
- **Collection pages by stored rows (2026-09-26):** `fetchAndTransformInBatches` fetches 1,000 rows a page with `includesPendingChanges = false`, drops rows deleted in the context, appends the context's unsaved inserts once, and stops on a short page of rows — never of DTOs, because the transformers `compactMap` away malformed rows. `BackupCollectionPagingTests` pins it: an unsaved insert, delete and edit past one page, and a skipped row on a full page. An in-memory store is read in one fetch per type: it gets `fetchOffset` + `fetchLimit` wrong on an unsorted fetch (the second page of 1,205 notes held one row).
- **Entity coverage is test-enforced:** `BackupCoverageTests` asserts `BackupEntityRegistry.allTypes` ≡ `BackupWriter.serializedEntityNames` ≡ `BackupImporter.handledEntityNames`, and that every model entity is either backed up or in an explicit, documented exclusion list (the 8 removed-feature tombstones). Adding an entity without backup coverage is a red test, not a future format version.
- **One entity table (2026-09-26):** `Backup/BackupEntityTable.swift` has one line per backed-up type (name, class, payload field, export transform, progress message). Collection, `BackupWriter.entitySerializations`, `BackupImporter.entityDecoders`, `BackupEntityRegistry.allTypes` and the per-type restore dedup all derive from it; DTOs conform to `BackupRowDTO`. Only the restore order (`BackupRestoreRun+CoreTypes` / `+PlanningTypes` / `+LaterTypes`) stays hand-written.
- **Model-driven rows for 31 types:** where a backup is a straight copy of the attributes, the DTO name is an alias of `ModelRow<Kind>` (`Backup/ModelRow.swift`) and the type has a short `ModelRowSpec` in `Backup/ModelRowKinds.swift`: `filling` (optional attributes the export writes "now"/a new id/`[]` for when nil — older builds need them to decode), `omitting` (device-local blobs), `parentIDs` (a parent's id written from a relationship) and `parents` (how restore re-links: keep, clear when not found, or always set). Everything else — keys, types, which keys are required — comes from the model, read once off the main actor (`BackupModelSchema`). Restore goes through `BackupEntityImporter.importRows`. The other 42 types keep hand-written DTOs (`Backup/BackupTypes*.swift`), transformers (`Backup/Export/`) and importers (`Backup/Import/`) because they reshape, validate or drop data. A new plain type is one table line plus one spec.
- **Output is pinned:** `BackupGoldenOutputTests` (+ `BackupGolden-v27.json`) compares a backup of the fully populated field-coverage fixture byte for byte and checks restore-then-export; `BackupSparseRowTests` (+ `BackupSparseRows-v27.json`, recorded from the hand-written code) pins nil fields, id-less records, id-only rows and missing parents for the 31 model-row types. Re-record only for an intended format change (`TEST_RUNNER_RECORD_BACKUP_GOLDEN=1` / `TEST_RUNNER_RECORD_BACKUP_SPARSE=1`; the file lands in the simulator app's tmp).
- Binary attributes are excluded from backups by design because they're regenerable (thumbnails, covers, file bookmarks). The **one exception is the album annotations** (format v21): highlight rectangles travel as plain numbers and Pencil ink travels as its PencilKit data, because neither can be recreated after a restore.

## Rules (moved from CLAUDE.md, 2026-10-04)

Moved verbatim from `Cosmic Daybook/CLAUDE.md` on 2026-10-04 so that file keeps only a pointer and the few rules a session needs before touching this area. These are still rules: follow them.

Format v37 (encrypted Apple Archive); reads v17–v37; entry point `Backup/Archive/BackupCoordinator.swift`. The design and the detailed working notes (format history, threading, streaming, restore) are in `Documentation/Architecture/BACKUP_SYSTEM.md`. Rules:

- **A new entity or attribute:** add a line to `Backup/BackupEntityTable.swift` (and a `ModelRowSpec` in `ModelRowKinds.swift` when the row is a straight copy). `BackupCoverageTests` fails until every model entity is backed up or explicitly excluded. Bump the format version and record it in BACKUP_SYSTEM.md.
- Output is pinned by `BackupGoldenOutputTests` and `BackupSparseRowTests`; re-record only for an intended format change.
- Encode, encryption, write, verification and decode run off the main actor through `@concurrent` (plain `nonisolated async` runs on the caller's actor in this project).
- **Merge restore is an upsert:** never delete and reinsert a row. Replace mode uses context-level deletes, not `NSBatchDeleteRequest`. Restore runs through `BackupTransactionManager.executeWithRollback`.
- `ClassroomMembership` is carried but never restored.
- Binary attributes are left out (regenerable), except album highlights and ink.
- `Cosmic Daybook Tests/Backup/BackupService+LegacyRestore.swift` is a frozen copy of the old restore for the equivalence tests; don't modernize it.
