//
//  SpotlightIndexer.swift
//  Cosmic Daybook
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
    nonisolated private static let logger = Logger.spotlight

    /// Fingerprint of the rows last handed to Spotlight. Lets a launch skip the
    /// index write entirely when nothing indexed has changed — the common case.
    private static let fingerprintKey = "SpotlightIndexer.lastIndexedFingerprint"
    /// The ids last handed to Spotlight, kept on this device so the next run
    /// can remove the ones no longer current (delete what's gone rather than
    /// wait for an expiry).
    private static let studentIDsKey = "SpotlightIndexer.lastIndexedStudentIDs"
    private static let lessonIDsKey = "SpotlightIndexer.lastIndexedLessonIDs"

    /// Re-indexes students and lessons when their indexed fields changed since
    /// the last successful run. Idempotent — safe on every launch.
    ///
    /// This used to fault every enrolled student and every lesson into the
    /// view context on the main actor and push them to Spotlight on each cold
    /// launch, whether or not anything had changed. Now the rows are read as
    /// plain values on a background context, hashed, and only sent when the
    /// hash differs from the last run's.
    ///
    /// Children who left (or are hidden as test students) and deleted lessons
    /// are removed first: indexing only ever added, so they stayed in phone
    /// search for good (2026-10-11 hunt, #39).
    static func reindexAll() async {
        let context = await AppBootstrapping.sharedCoreDataStack().container.newBackgroundContext()
        let hiddenNames = TestStudentsFilter.normalizedHiddenNames()
        // Read and hash on the context's queue. The fingerprint joins and
        // hashes every indexed row, and it used to be computed back on the
        // main actor after the read.
        let (snapshot, fingerprint) = await context.perform {
            let snapshot = Self.loadSnapshot(in: context, hiddenStudentNames: hiddenNames)
            return (snapshot, snapshot.fingerprint)
        }

        let defaults = UserDefaults.standard
        // Before the id lists existed, the index may still hold children who
        // left: run once to clear them even when the rows haven't changed.
        let hasIDLists = defaults.stringArray(forKey: studentIDsKey) != nil
            && defaults.stringArray(forKey: lessonIDsKey) != nil
        if hasIDLists, fingerprint == defaults.string(forKey: fingerprintKey) {
            logger.debug("Spotlight index unchanged; skipping reindex.")
            return
        }

        var indexed = true
        if await replace(
            StudentEntity.self, with: snapshot.students.map { $0.entity },
            previousKey: studentIDsKey, label: "students"
        ) == false { indexed = false }
        if await replace(
            LessonEntity.self, with: snapshot.lessons.map { $0.entity },
            previousKey: lessonIDsKey, label: "lessons"
        ) == false { indexed = false }
        if indexed {
            defaults.set(fingerprint, forKey: fingerprintKey)
        }
    }

    // MARK: - Removals

    /// What to remove from Spotlight before indexing the current set.
    nonisolated enum Removal: Equatable, Sendable {
        /// No record of what was indexed before: clear the type once.
        case everything
        /// The ids indexed last time that aren't current now (may be empty).
        case ids([UUID])
    }

    /// The previous run's ids (as stored) against the current ones.
    nonisolated static func removals(previous: [String]?, current: [UUID]) -> Removal {
        guard let previous else { return .everything }
        let currentSet = Set(current)
        let gone = previous.compactMap(UUID.init(uuidString:)).filter { !currentSet.contains($0) }
        return .ids(gone.sorted { $0.uuidString < $1.uuidString })
    }

    // MARK: - Snapshot

    nonisolated fileprivate struct StudentRow: Sendable {
        let id: UUID
        let firstName: String
        let lastName: String
        let nickname: String?

        var entity: StudentEntity {
            StudentEntity(id: id, firstName: firstName, lastName: lastName, nickname: nickname)
        }

        var line: String { "S\u{1F}\(id.uuidString)\u{1F}\(firstName)\u{1F}\(lastName)\u{1F}\(nickname ?? "")" }
    }

    nonisolated fileprivate struct LessonRow: Sendable {
        let id: UUID
        let name: String
        let area: String
        let sequence: String

        var entity: LessonEntity {
            LessonEntity(id: id, name: name, area: area, sequence: sequence)
        }

        var line: String { "L\u{1F}\(id.uuidString)\u{1F}\(name)\u{1F}\(area)\u{1F}\(sequence)" }
    }

    nonisolated struct Snapshot: Sendable {
        fileprivate let students: [StudentRow]
        fileprivate let lessons: [LessonRow]

        var studentIDs: [UUID] { students.map(\.id) }

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
    /// Enrolled students only, without the hidden test students
    /// (`TestStudentsFilter.normalizedHiddenNames`, matched on the full name).
    nonisolated static func loadSnapshot(
        in context: NSManagedObjectContext,
        hiddenStudentNames: Set<String>
    ) -> Snapshot {
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
                let student = StudentRow(
                    id: id,
                    firstName: row["firstName"] as? String ?? "",
                    lastName: row["lastName"] as? String ?? "",
                    nickname: row["nickname"] as? String
                )
                // The same full-name match `TestStudentsFilter` makes.
                let fullName = "\(student.firstName) \(student.lastName)".normalizedForComparison()
                guard !hiddenStudentNames.contains(fullName) else { continue }
                students.append(student)
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

    /// Removes what is no longer current, then indexes `entities` and records
    /// their ids. Returns false when Spotlight refused either step; the ids
    /// are kept as they were then, so the next run tries the removal again.
    private static func replace<E: IndexedEntity>(
        _ type: E.Type,
        with entities: [E],
        previousKey: String,
        label: String
    ) async -> Bool where E.ID == UUID {
        let defaults = UserDefaults.standard
        let current = entities.map(\.id)
        let searchIndex = CSSearchableIndex.default()
        do {
            switch removals(previous: defaults.stringArray(forKey: previousKey), current: current) {
            case .everything:
                try await searchIndex.deleteAppEntities(ofType: type)
            case .ids(let gone) where !gone.isEmpty:
                try await searchIndex.deleteAppEntities(identifiedBy: gone, ofType: type)
                logger.info("Removed \(gone.count) \(label) from Spotlight.")
            case .ids:
                break
            }
        } catch {
            logger.warning("Failed to remove old \(label) from Spotlight: \(error.localizedDescription)")
            return false
        }
        guard await index(entities, label: label) else { return false }
        defaults.set(current.map(\.uuidString), forKey: previousKey)
        return true
    }

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
