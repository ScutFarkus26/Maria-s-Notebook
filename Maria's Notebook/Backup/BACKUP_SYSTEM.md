# Backup & Restore System

**Last Updated:** 2026-06-13

> Authoritative summary lives in the project root `CLAUDE.md` ("Backup System").
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

### The Backup2 module (current code path)

| File | Purpose |
|------|---------|
| `Backup2/BackupCoordinator.swift` | The single app-facing API. UI calls `exportBackup`, `previewImport`, `importBackup`, `verifyBackup`. |
| `Backup2/BackupArchive.swift` | Low-level AppleArchive wrapper. Encrypted write (`AA01`), read of both encrypted v19 and plain v17/v18 (`pbz*`), magic-byte detection, per-entry size guard. |
| `Backup2/BackupEncryptionKeyStore.swift` | The 256-bit symmetric key in the iCloud Keychain (synchronizable, after-first-unlock). `fetchOrCreateKey()` for export, `requireKey()` for restore. |
| `Backup2/BackupWriter.swift` | Builds a v19 backup: collect payload (main actor) → serialize NDJSON + manifest → write encrypted temp file → verify → atomic rename (all off-main). Aborts on any entity encode failure. |
| `Backup2/BackupReader.swift` | Decodes an archive into manifest + entries + preferences. `verifyStructure` streams the archive counting rows without holding the payload. |
| `Backup2/BackupImporter.swift` | Off-main: reconstructs a `BackupPayload` from NDJSON entries (table-driven dispatch). On-main: hands it to `BackupService.importPayload`. Surfaces decode skips as warnings. |

### Shared services (reused by Backup2)

| File | Purpose |
|------|---------|
| `Backup/BackupService+DataCollection.swift` | `collectPayload` — fetches every entity type in batches, runs DTO transformers. |
| `Backup/BackupService+Restoration.swift` | `importPayload` — dedup, replace-mode clear, ordered entity import, denormalized-field repair, CloudKit export wait. |
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
| `AppCore/BackupBackgroundTaskManager.swift` | iOS — `BGProcessingTask` registration + scheduling. |
| `AppCore/MariasNotebookApp.swift` | iOS scene-phase `.background` trigger (under a `UIApplication` background-task assertion); starts the interval loop. |

---

## Format Versions

| Version | Container | Notes |
|---------|-----------|-------|
| v5–v16 | JSON envelope + LZFSE (+ SHA256 / AES-GCM in some) | **No longer readable by the app.** Recover via the external Python/`aa` recipe. |
| v17 | Plain LZFSE Apple Archive (`pbz*`) | First NDJSON-in-archive format. Read-only now. |
| v18 | Plain LZFSE Apple Archive (`pbz*`) | Adds DayPad, YearPlanEntry, LessonSequenceSettings, Story, BookClub entries. Read-only now. |
| **v19** | **Encrypted Apple Archive (`AEA1`)** | **Current write format.** AES-CTR + HMAC, key from iCloud Keychain. Same entry layout as v18. |

`BackupReader.supportedFormatVersions = 17...19`.

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
2. `collectPayload` fetches all entities as DTOs (main actor / view-context queue).
3. Off the main actor: serialize NDJSON + manifest, fetch/create the Keychain key.
4. Write the encrypted archive to a hidden `.partial` temp file in the destination directory (`0600`).
5. **Verify:** re-read via `BackupReader.verifyStructure` — manifest must round-trip and every entity's NDJSON row count must match the manifest.
6. Atomically rename the temp file into place. On any failure the temp file is removed and nothing lands at the destination.

Any single entity type failing to encode aborts the entire export — a backup
silently missing data is worse than a failed one.

---

## Restore Flow

1. `BackupCoordinator.importBackup` → `BackupTransactionManager.executeWithRollback`.
2. For `.replace`, a safety checkpoint (current-format backup) is written first; if it fails, the restore aborts before deleting anything.
3. `BackupImporter.decodeArchive` (off-main) reads + decrypts + JSON-decodes into a `BackupPayload`.
4. `BackupService.importPayload` (main actor):
   - dedup the payload,
   - for `.replace`: context-level delete of every backed-up type (emits CloudKit tombstones — never `NSBatchDeleteRequest`),
   - import entities in dependency order using a lazily built `BackupEntityIndex` for existence/relationship checks,
   - `save()`,
   - repair denormalized fields,
   - apply preferences.
5. The CloudKit export wait is subscribed **before** `save()` so a fast export isn't missed; it blocks up to 30 s, then reports "still syncing in background."
6. On any import failure, the transaction manager rolls back to the checkpoint.

---

## Encryption & Key Management

- AES-CTR + HMAC via `ArchiveEncryptionContext` (profile `hkdf_sha256_aesctr_hmac__symmetric__none`).
- 256-bit `SymmetricKey` in the **iCloud Keychain** — synchronizable so a backup made on one device restores on another signed into the same Apple ID (the lost-device case backups exist for). `kSecAttrAccessibleAfterFirstUnlock` lets scheduled/background backups run while locked.
- Files are `0600`.
- Restore on a device whose Keychain hasn't synced the key yet fails with an actionable message rather than deep inside stream setup.

---

## Automatic Backups

- **Triggers:** macOS quit, iOS background (scene phase + `BGProcessingTask`), in-app interval loop, pre-destructive.
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
4. Add a decoder to `BackupImporter.entityDecoders` and an importer call in `BackupService+Restoration.swift`.
5. Bump `BackupWriter.formatVersion` and extend `BackupReader.supportedFormatVersions` if the addition is structural.

---

## Not Implemented

- **Incremental/delta backups** — `BackupChangeTracker` already provides the persistent-history plumbing; deltas would build on it.
- **Legacy (v5–v16) import** — intentionally removed; external recovery only.
- **Document/attachment payloads** — backups carry metadata, not imported files (by design; surfaced as an export warning).

---

## Testing

- `Maria's Notebook Tests/BackupRoundTripTests.swift` — end-to-end round trips, encryption/verification, merge mode, corruption rejection, v18 entity fidelity.
- `Maria's Notebook Tests/BackupCoverageTests.swift` — coverage exhaustiveness (registry ≡ writer ≡ importer ≡ model − exclusions).
- `Maria's Notebook Tests/BackupCheckpointSafetyTests.swift` — checkpoint failure aborts before any destructive delete.

```bash
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  xcodebuild test -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" \
    -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
    -only-testing:"Maria's Notebook Tests/BackupRoundTripTests" \
    -only-testing:"Maria's Notebook Tests/BackupCoverageTests" \
    -only-testing:"Maria's Notebook Tests/BackupCheckpointSafetyTests"
```
