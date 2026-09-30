import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins how the backup treats the data `BackupGoldenOutputTests` never has:
/// records whose optional attributes are all nil, a record with no `id`, a
/// row holding nothing but an `id` (an older backup), and a child whose parent
/// can't be found on restore. The reference, `BackupSparseRows-v27.json`, was
/// recorded from the hand-written DTOs, transformers and importers before the
/// types listed in `entityNames` moved to `ModelRow`; this test holds the
/// model-driven code to exactly what they did.
///
/// Re-record only for an intended change, with `TEST_RUNNER_RECORD_BACKUP_SPARSE=1`.
@Suite("Backup sparse rows", .serialized)
@MainActor
struct BackupSparseRowTests {
    private final class BundleToken {}
    private static let referenceName = "BackupSparseRows-v27"

    /// The entity types written through `ModelRow`.
    static let entityNames = [
        "LessonRecallCheck", "MeetingTemplate", "Track", "Schedule", "GoingOut", "ClassroomJob",
        "CalendarNote", "ClassroomMembership", "StudentFocusItem", "DayPad", "YearPlanEntry",
        "LessonSequenceSettings", "BookClubSession", "Guardian", "ParentCommunication", "AlbumBookmark",
        "AlbumPageNote", "AlbumRecentVisit", "AlbumReadingPosition", "OrderItem", "ProposedSolution",
        "WorkStep", "SampleWorkStep", "TrackStep", "TodoSubtask", "LessonAttachment", "NoteStudentLink",
        "JobAssignment", "BookClubMeeting", "StudentTrackEnrollment", "MeetingWorkReview", "AttendanceDayLock",
        "SupplyTransaction", "AttendanceEmailSend", "AttendanceEmailSettings"
    ]

    /// A child's link to its parent: the row key, the relationship, the parent
    /// entity, and whether the key is an attribute (a UUID string) rather than
    /// a written parent id.
    private struct ParentCase {
        let child: String
        let key: String
        let relationship: String
        let parent: String
        let isAttribute: Bool

        init(_ child: String, _ key: String, _ relationship: String, _ parent: String, _ isAttribute: Bool) {
            (self.child, self.key, self.relationship, self.parent, self.isAttribute) =
                (child, key, relationship, parent, isAttribute)
        }
    }

    private static let parentLinks: [ParentCase] = [
        ParentCase("ProposedSolution", "topicID", "topic", "CommunityTopic", false),
        ParentCase("WorkStep", "workID", "work", "WorkModel", false),
        ParentCase("SampleWorkStep", "sampleWorkID", "sampleWork", "SampleWork", false),
        ParentCase("TrackStep", "trackID", "track", "Track", false),
        ParentCase("TodoSubtask", "todoID", "todo", "TodoItem", false),
        ParentCase("LessonAttachment", "lessonID", "lesson", "Lesson", false),
        ParentCase("NoteStudentLink", "noteID", "note", "Note", true),
        ParentCase("JobAssignment", "jobID", "job", "ClassroomJob", true),
        ParentCase("BookClubMeeting", "sessionID", "session", "BookClubSession", true),
        ParentCase("StudentTrackEnrollment", "trackID", "track", "Track", true),
        ParentCase("MeetingWorkReview", "meetingID", "meeting", "StudentMeeting", true),
        ParentCase("SupplyTransaction", "supplyID", "supply", "Supply", true)
    ]

    @Test("Sparse records, id-only rows and missing parents behave as the hand-written backup did")
    func matchesReference() async throws {
        var observed: [String: [String: [String]]] = [:]
        observed["sparseExport"] = try Self.sparseExport()
        observed["idOnlyRow"] = try Self.idOnlyRows()
        observed["missingParent"] = try await Self.missingParents()

        if ProcessInfo.processInfo.environment["RECORD_BACKUP_SPARSE"] == "1" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(Self.referenceName).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(observed).write(to: url)
            Issue.record("Recorded the sparse-row reference to \(url.path); copy it over \(Self.referenceName).json")
            return
        }
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: Self.referenceName, withExtension: "json"),
            "Missing \(Self.referenceName).json in the test bundle"
        )
        let reference = try JSONDecoder().decode([String: [String: [String]]].self, from: Data(contentsOf: url))
        for (section, entries) in reference {
            for (name, expected) in entries.sorted(by: { $0.key < $1.key }) {
                let actual = observed[section]?[name] ?? []
                #expect(actual == expected, "\(section) \(name): now \(actual), recorded \(expected)")
            }
            let extra = Set(observed[section]?.keys ?? [:].keys).subtracting(entries.keys)
            #expect(extra.isEmpty, "\(section): not in the reference: \(extra.sorted())")
        }
    }

    // MARK: - Sparse export

    /// Per entity: the written rows for one record with a fixed id and every
    /// optional attribute nil, and one record with no id at all. Values the
    /// export makes up (a new id, the current time) are shown as placeholders.
    private static func sparseExport() throws -> [String: [String]] {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        var known: Set<String> = []
        for (index, name) in entityNames.enumerated() {
            let withID = NSEntityDescription.insertNewObject(forEntityName: name, into: context)
            let id = fixedUUID(index)
            withID.setValue(id, forKey: "id")
            known.insert(id.uuidString)
            _ = NSEntityDescription.insertNewObject(forEntityName: name, into: context)
        }
        #expect(CoreDataTestHelpers.save(context), "Sparse fixture save failed")
        let entries = try BackupWriter.serializeEntries(from: BackupService().collectPayload(viewContext: context))
        var result: [String: [String]] = [:]
        for name in entityNames {
            let entry = entries.first { $0.entityName == name }
            let body = entry.flatMap { String(bytes: $0.ndjson, encoding: .utf8) } ?? ""
            result[name] = body.split(separator: "\n").map { normalize(String($0), known: known) }.sorted()
        }
        return result
    }

    private static func normalize(_ row: String, known: Set<String>) -> String {
        var text = row
        let uuid = /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/
        for match in row.matches(of: uuid) where !known.contains(String(match.output)) {
            text = text.replacingOccurrences(of: String(match.output), with: "<new id>")
        }
        let date = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/
        let formatter = ISO8601DateFormatter()
        for match in row.matches(of: date) {
            if let value = formatter.date(from: String(match.output)), abs(value.timeIntervalSinceNow) < 3_600 {
                text = text.replacingOccurrences(of: String(match.output), with: "<now>")
            }
        }
        return text
    }

    // MARK: - Id-only rows

    /// Per entity: whether a row holding only an `id` decodes ("restored") or
    /// is rejected with the rest of its entry ("rejected").
    private static func idOnlyRows() throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (index, name) in entityNames.enumerated() {
            let row = Data(#"{"id":"\#(fixedUUID(900 + index).uuidString)"}"#.utf8)
            let store = CoreDataStack.sharedEntityNames.contains(name) ? "shared" : "private"
            let entry = BackupEntityEntry(entityName: name, storeName: store, count: 1, ndjson: row + Data([0x0A]))
            let (payload, _) = BackupImporter.reconstructPayload(from: decoded([entry]))
            let written = try BackupWriter.serializeEntries(from: payload).contains { $0.entityName == name }
            result[name] = [written ? "restored" : "rejected"]
        }
        return result
    }

    // MARK: - Missing parents

    /// Per child key: what a merge restore does to a linked child whose row
    /// names a parent that can't be found, is left out, or isn't an id.
    private static func missingParents() async throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        for link in parentLinks {
            var outcomes: [String] = []
            var scenarios: [(String, Any?)] = [("not found", fixedUUID(700).uuidString)]
            if link.isAttribute {
                scenarios.append(("not an id", "not-a-uuid"))
            } else {
                scenarios.append(("left out", nil))
            }
            for (scenario, replacement) in scenarios {
                let outcome = try await restoreChild(link: link, replacement: replacement)
                outcomes.append("\(scenario): \(outcome)")
            }
            result["\(link.child).\(link.relationship)"] = outcomes
        }
        return result
    }

    private static func restoreChild(
        link: ParentCase,
        replacement: Any?
    ) async throws -> String {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let parent = NSEntityDescription.insertNewObject(forEntityName: link.parent, into: context)
        let parentID = fixedUUID(1)
        parent.setValue(parentID, forKey: "id")
        let child = NSEntityDescription.insertNewObject(forEntityName: link.child, into: context)
        let childID = fixedUUID(2)
        child.setValue(childID, forKey: "id")
        child.setValue(parent, forKey: link.relationship)
        if link.isAttribute { child.setValue(parentID.uuidString, forKey: link.key) }
        #expect(CoreDataTestHelpers.save(context), "Parent fixture save failed for \(link.child)")

        var entries = try BackupWriter.serializeEntries(from: BackupService().collectPayload(viewContext: context))
        guard let index = entries.firstIndex(where: { $0.entityName == link.child }) else { return "child not written" }
        let lines = entries[index].ndjson.split(separator: 0x0A).map { line -> Data in
            guard var row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                return Data(line)
            }
            row[link.key] = replacement
            return (try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])) ?? Data(line)
        }
        var body = Data()
        for line in lines { body.append(line); body.append(0x0A) }
        let old = entries[index]
        entries[index] = BackupEntityEntry(
            entityName: old.entityName, storeName: old.storeName, count: old.count, ndjson: body
        )

        let (payload, _) = BackupImporter.reconstructPayload(from: decoded(entries))
        _ = try await BackupService().importPayload(
            payload: payload,
            envelope: BackupEnvelope(
                formatVersion: BackupWriter.formatVersion, encrypted: false, createdAt: Date(),
                fileName: "sparse-parent", entityCounts: [:]
            ),
            viewContext: context,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )
        let linked = child.value(forKey: link.relationship) as? NSManagedObject
        if linked == nil { return "cleared" }
        return linked?.value(forKey: "id") as? UUID == parentID ? "kept" : "changed"
    }

    // MARK: - Helpers

    private static func decoded(_ entries: [BackupEntityEntry]) -> BackupReader.DecodedBackup {
        BackupReader.DecodedBackup(
            manifest: BackupArchiveManifest(
                formatVersion: BackupWriter.formatVersion, createdAt: Date(),
                appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
            ),
            entries: entries,
            preferences: nil
        )
    }

    private static func fixedUUID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", index)) ?? UUID()
    }
}
