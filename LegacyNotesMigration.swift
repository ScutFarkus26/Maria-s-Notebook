import Foundation
import SwiftData
import CryptoKit

enum LegacyNotesMigration {
    static let didMigrateKey = "DidMigrateLegacyScopedNotes_v1"

    static func runIfNeeded(modelContext: ModelContext) {
        // Skip migration entirely during ephemeral/in-memory sessions to avoid setting flags for non-persistent data
        if UserDefaults.standard.bool(forKey: MariasToolboxApp.ephemeralSessionFlagKey) {
            return
        }
        
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: didMigrateKey) { return }

        do {
            var pendingSaves = 0
            pendingSaves += try migrateStudentLessonNotes(context: modelContext)
            pendingSaves += try migrateStudentLessonFollowUps(context: modelContext)
            pendingSaves += try migrateWorkNotes(context: modelContext)
            if pendingSaves > 0 {
                try modelContext.save()
            }
            defaults.set(true, forKey: didMigrateKey)
        } catch {
            // Do not set the flag on failure; log and return
            print("LegacyNotesMigration error:", error)
        }
    }

    // MARK: - Migrations

    @discardableResult
    private static func migrateStudentLessonNotes(context: ModelContext) throws -> Int {
        let fetch = FetchDescriptor<StudentLesson>()
        let lessons = try context.fetch(fetch)
        var inserted = 0
        for sl in lessons {
            let body = normalize(sl.notes)
            if body.isEmpty { continue }
            let fp = fingerprint(parts: ["StudentLesson", sl.id.uuidString, "notes", body])
            if hasExistingScopedNote(parentNotes: sl.scopedNotes, fingerprint: fp) { continue }
            if existsNoteWithFingerprint(fp, context: context) { continue }
            let note = ScopedNote(
                body: body,
                scope: .all,
                legacyFingerprint: fp,
                studentLesson: sl,
                work: nil
            )
            note.createdAt = sl.givenAt ?? sl.createdAt
            note.updatedAt = note.createdAt
            sl.scopedNotes.append(note)
            inserted += 1
            if inserted % 100 == 0 { try context.save() }
        }
        return inserted
    }

    @discardableResult
    private static func migrateStudentLessonFollowUps(context: ModelContext) throws -> Int {
        let fetch = FetchDescriptor<StudentLesson>()
        let lessons = try context.fetch(fetch)
        var inserted = 0
        for sl in lessons {
            let raw = sl.followUpWork
            let body = normalize(raw)
            if body.isEmpty { continue }
            let fp = fingerprint(parts: ["StudentLesson", sl.id.uuidString, "followUpWork", body])
            if hasExistingScopedNote(parentNotes: sl.scopedNotes, fingerprint: fp) { continue }
            if existsNoteWithFingerprint(fp, context: context) { continue }
            let note = ScopedNote(
                body: body,
                scope: .all,
                legacyFingerprint: fp,
                studentLesson: sl,
                work: nil
            )
            note.createdAt = sl.givenAt ?? sl.createdAt
            note.updatedAt = note.createdAt
            sl.scopedNotes.append(note)
            inserted += 1
            if inserted % 100 == 0 { try context.save() }
        }
        return inserted
    }

    @discardableResult
    private static func migrateWorkNotes(context: ModelContext) throws -> Int {
        let fetch = FetchDescriptor<WorkModel>()
        let works = try context.fetch(fetch)
        var inserted = 0
        for w in works {
            let body = normalize(w.notes)
            if body.isEmpty { continue }
            let fp = fingerprint(parts: ["WorkModel", w.id.uuidString, "notes", body])
            if hasExistingScopedNote(parentNotes: w.scopedNotes, fingerprint: fp) { continue }
            if existsNoteWithFingerprint(fp, context: context) { continue }
            let note = ScopedNote(
                body: body,
                scope: .all,
                legacyFingerprint: fp,
                studentLesson: nil,
                work: w
            )
            note.createdAt = w.createdAt
            note.updatedAt = note.createdAt
            w.scopedNotes.append(note)
            inserted += 1
            if inserted % 100 == 0 { try context.save() }
        }
        return inserted
    }

    // MARK: - Helpers

    private static func existsNoteWithFingerprint(_ fingerprint: String, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ScopedNote>(predicate: #Predicate { $0.legacyFingerprint == fingerprint })
        let matches = (try? context.fetch(descriptor)) ?? []
        return !matches.isEmpty
    }

    private static func hasExistingScopedNote(parentNotes: [ScopedNote], fingerprint: String) -> Bool {
        return parentNotes.contains { $0.legacyFingerprint == fingerprint }
    }

    static func fingerprint(parts: [String]) -> String {
        let joined = parts.joined(separator: "|")
        let data = Data(joined.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
