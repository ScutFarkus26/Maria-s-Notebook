//
//  SpotlightIndexer.swift
//  Maria's Notebook
//
//  Indexes students and lessons into Spotlight's semantic index so they appear
//  in phone search and can be referenced by the modern Siri / Apple Intelligence.
//  Indexing AppEntities (not raw CSSearchableItems) links each result back to its
//  Open intent, so tapping a result routes into the app.
//

import AppIntents
import CoreData
import CoreSpotlight
import CryptoKit
import OSLog

enum SpotlightIndexer {
    nonisolated private static let logger = Logger.app(category: "Spotlight")

    /// Fingerprint of the rows last handed to Spotlight. Lets a launch skip the
    /// index write entirely when nothing indexed has changed — the common case.
    private static let fingerprintKey = "SpotlightIndexer.lastIndexedFingerprint"

    /// Re-indexes students and lessons when their indexed fields changed since
    /// the last successful run. Idempotent — safe on every launch.
    ///
    /// This used to fault every enrolled student and every lesson into the
    /// view context on the main actor and push them to Spotlight on each cold
    /// launch, whether or not anything had changed. Now the rows are read as
    /// plain values on a background context, hashed, and only sent when the
    /// hash differs from the last run's.
    static func reindexAll() async {
        let context = AppBootstrapping.getSharedCoreDataStack().container.newBackgroundContext()
        let snapshot = await context.perform { Self.loadSnapshot(in: context) }

        let fingerprint = snapshot.fingerprint
        if fingerprint == UserDefaults.standard.string(forKey: fingerprintKey) {
            logger.debug("Spotlight index unchanged; skipping reindex.")
            return
        }

        var indexed = true
        if await index(snapshot.students.map { $0.entity }, label: "students") == false { indexed = false }
        if await index(snapshot.lessons.map { $0.entity }, label: "lessons") == false { indexed = false }
        if indexed {
            UserDefaults.standard.set(fingerprint, forKey: fingerprintKey)
        }
    }

    // MARK: - Snapshot

    nonisolated private struct StudentRow: Sendable {
        let id: UUID
        let firstName: String
        let lastName: String
        let nickname: String?

        var entity: StudentEntity {
            StudentEntity(id: id, firstName: firstName, lastName: lastName, nickname: nickname)
        }

        var line: String { "S\u{1F}\(id.uuidString)\u{1F}\(firstName)\u{1F}\(lastName)\u{1F}\(nickname ?? "")" }
    }

    nonisolated private struct LessonRow: Sendable {
        let id: UUID
        let name: String
        let area: String
        let sequence: String

        var entity: LessonEntity {
            LessonEntity(id: id, name: name, area: area, sequence: sequence)
        }

        var line: String { "L\u{1F}\(id.uuidString)\u{1F}\(name)\u{1F}\(area)\u{1F}\(sequence)" }
    }

    nonisolated private struct Snapshot: Sendable {
        let students: [StudentRow]
        let lessons: [LessonRow]

        /// Stable across launches (unlike `Hasher`, which is randomly seeded).
        var fingerprint: String {
            var text = ""
            for row in students { text += row.line; text += "\n" }
            for row in lessons { text += row.line; text += "\n" }
            let digest = SHA256.hash(data: Data(text.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Reads just the indexed columns as dictionaries — no managed objects are
    /// faulted in — and orders rows by id so the fingerprint is deterministic.
    nonisolated private static func loadSnapshot(in context: NSManagedObjectContext) -> Snapshot {
        let studentRequest = NSFetchRequest<NSDictionary>(entityName: "Student")
        studentRequest.resultType = .dictionaryResultType
        studentRequest.propertiesToFetch = ["id", "firstName", "lastName", "nickname"]
        studentRequest.predicate = NSPredicate(
            format: "enrollmentStatusRaw == %@",
            CDStudent.EnrollmentStatus.enrolled.rawValue
        )

        let lessonRequest = NSFetchRequest<NSDictionary>(entityName: "Lesson")
        lessonRequest.resultType = .dictionaryResultType
        lessonRequest.propertiesToFetch = ["id", "name", "area", "sequence"]

        var students: [StudentRow] = []
        var lessons: [LessonRow] = []
        do {
            for row in try context.fetch(studentRequest) {
                guard let id = row["id"] as? UUID else { continue }
                students.append(StudentRow(
                    id: id,
                    firstName: row["firstName"] as? String ?? "",
                    lastName: row["lastName"] as? String ?? "",
                    nickname: row["nickname"] as? String
                ))
            }
            for row in try context.fetch(lessonRequest) {
                guard let id = row["id"] as? UUID,
                      let name = row["name"] as? String, !name.isEmpty else { continue }
                lessons.append(LessonRow(
                    id: id,
                    name: name,
                    area: row["area"] as? String ?? "",
                    sequence: row["sequence"] as? String ?? ""
                ))
            }
        } catch {
            logger.warning("Failed to read rows for Spotlight: \(error.localizedDescription)")
        }
        students.sort { $0.id.uuidString < $1.id.uuidString }
        lessons.sort { $0.id.uuidString < $1.id.uuidString }
        return Snapshot(students: students, lessons: lessons)
    }

    // MARK: - Indexing

    /// Returns false only when Spotlight rejected the write; an empty set is a
    /// no-op that still counts as indexed (matching the previous behavior).
    private static func index<E: IndexedEntity>(_ entities: [E], label: String) async -> Bool {
        guard !entities.isEmpty else { return true }
        do {
            try await CSSearchableIndex.default().indexAppEntities(entities)
            logger.info("Indexed \(entities.count) \(label) into Spotlight.")
            return true
        } catch {
            logger.warning("Failed to index \(label) into Spotlight: \(error.localizedDescription)")
            return false
        }
    }
}
