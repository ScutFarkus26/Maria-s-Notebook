import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// `BackupSchema25Tests`' records and the restores it runs: one record of each
// type schema 25 touches, the values it reads back, and a merge of a backup's
// entries as a backup of a given format holds them.

extension BackupSchema25Tests {

    /// One record of each type schema 25 touches, every new field set (a
    /// false flag included), one presentation record with none of hers, and
    /// one level change.
    func seedSchema25Records(into context: NSManagedObjectContext) {
        Self.insert("WorkModel", [
            "id": workID, "title": "Long division", "studentID": studentID.uuidString,
            "assignmentID": assignmentID.uuidString, "isSharedRow": true
        ], into: context)
        Self.insert("LessonPresentation", [
            "id": setPresentationID, "studentID": studentID.uuidString, "lessonID": UUID().uuidString,
            "needsPractice": true, "needsAnotherPresentation": false, "manuallyUnblocked": true
        ], into: context)
        Self.insert("LessonPresentation", [
            "id": unsetPresentationID, "studentID": studentID.uuidString, "lessonID": UUID().uuidString
        ], into: context)
        Self.insert("Guardian", [
            "id": guardianID, "studentID": studentID.uuidString, "name": "A Parent", "personID": personID.uuidString
        ], into: context)
        Self.insert("AttendanceEmailSettings", [
            "id": settingsID, "classroomTimeZoneID": "America/Chicago",
            "sessionFirstDay": firstDay, "sessionLastDay": lastDay
        ], into: context)
        Self.insert("LevelChange", [
            "id": levelChangeID, "studentID": studentID.uuidString, "fromLevelRaw": "Lower", "toLevelRaw": "Upper",
            "changedOn": changedOn, "createdAt": stamped, "modifiedAt": stamped
        ], into: context)
    }

    /// What `seedSchema25Records` set, read back from `context`.
    func expectSchema25Values(in context: NSManagedObjectContext) throws {
        let work = try Self.record("WorkModel", workID, in: context)
        #expect(work.value(forKey: "assignmentID") as? String == assignmentID.uuidString)
        #expect(work.value(forKey: "isSharedRow") as? Bool == true)
        let set = try Self.record("LessonPresentation", setPresentationID, in: context)
        #expect(set.value(forKey: "needsPractice") as? Bool == true)
        #expect(set.value(forKey: "needsAnotherPresentation") as? Bool == false)
        #expect(set.value(forKey: "manuallyUnblocked") as? Bool == true)
        let unset = try Self.record("LessonPresentation", unsetPresentationID, in: context)
        for key in ["needsPractice", "needsAnotherPresentation", "manuallyUnblocked"] {
            #expect(unset.value(forKey: key) == nil, "an unset \(key) came back set")
        }
        try expectOtherSchema25Values(in: context)
    }

    /// The guardian's, the settings' and the level change's.
    private func expectOtherSchema25Values(in context: NSManagedObjectContext) throws {
        let guardian = try Self.record("Guardian", guardianID, in: context)
        #expect(guardian.value(forKey: "personID") as? String == personID.uuidString)
        let settings = try Self.record("AttendanceEmailSettings", settingsID, in: context)
        #expect(settings.value(forKey: "classroomTimeZoneID") as? String == "America/Chicago")
        #expect(settings.value(forKey: "sessionFirstDay") as? Date == firstDay)
        #expect(settings.value(forKey: "sessionLastDay") as? Date == lastDay)
        let change = try Self.record("LevelChange", levelChangeID, in: context)
        #expect(change.value(forKey: "studentID") as? String == studentID.uuidString)
        #expect(change.value(forKey: "fromLevelRaw") as? String == "Lower")
        #expect(change.value(forKey: "toLevelRaw") as? String == "Upper")
        #expect(change.value(forKey: "changedOn") as? Date == changedOn)
        #expect(change.value(forKey: "createdAt") as? Date == stamped)
        #expect(change.value(forKey: "modifiedAt") as? Date == stamped)
    }

    /// The first record of each touched type in the format-46 fixture.
    struct Fixture46IDs {
        let work: UUID
        let presentation: UUID
        let guardian: UUID
        let settings: UUID
    }

    func setSchema25Fields(on ids: Fixture46IDs, in context: NSManagedObjectContext) throws {
        let work = try Self.record("WorkModel", ids.work, in: context)
        work.setValue(assignmentID.uuidString, forKey: "assignmentID")
        work.setValue(true, forKey: "isSharedRow")
        let presentation = try Self.record("LessonPresentation", ids.presentation, in: context)
        presentation.setValue(false, forKey: "needsPractice")
        presentation.setValue(true, forKey: "needsAnotherPresentation")
        presentation.setValue(true, forKey: "manuallyUnblocked")
        try Self.record("Guardian", ids.guardian, in: context).setValue(personID.uuidString, forKey: "personID")
        let settings = try Self.record("AttendanceEmailSettings", ids.settings, in: context)
        settings.setValue("America/Chicago", forKey: "classroomTimeZoneID")
        settings.setValue(firstDay, forKey: "sessionFirstDay")
        settings.setValue(lastDay, forKey: "sessionLastDay")
    }

    /// The fields `setSchema25Fields` set: still there when `optionalsKept`,
    /// otherwise every optional one cleared and the work flag still there.
    /// A cleared assignment doesn't stay nil: the after-restore fill gives the
    /// row one again, its own (`WorkAssignmentFill`), and leaves the flag.
    func expectSchema25Fields(on ids: Fixture46IDs, in context: NSManagedObjectContext, optionalsKept: Bool) throws {
        let work = try Self.record("WorkModel", ids.work, in: context)
        #expect(work.value(forKey: "isSharedRow") as? Bool == true)
        let ownAssignment = optionalsKept ? assignmentID.uuidString : ids.work.uuidString
        #expect(work.value(forKey: "assignmentID") as? String == ownAssignment)
        let presentation = try Self.record("LessonPresentation", ids.presentation, in: context)
        #expect(presentation.value(forKey: "needsPractice") as? Bool == (optionalsKept ? false : nil))
        #expect(presentation.value(forKey: "needsAnotherPresentation") as? Bool == (optionalsKept ? true : nil))
        #expect(presentation.value(forKey: "manuallyUnblocked") as? Bool == (optionalsKept ? true : nil))
        let guardian = try Self.record("Guardian", ids.guardian, in: context)
        #expect(guardian.value(forKey: "personID") as? String == (optionalsKept ? personID.uuidString : nil))
        let settings = try Self.record("AttendanceEmailSettings", ids.settings, in: context)
        #expect(settings.value(forKey: "classroomTimeZoneID") as? String == (optionalsKept ? "America/Chicago" : nil))
        #expect(settings.value(forKey: "sessionFirstDay") as? Date == (optionalsKept ? firstDay : nil))
        #expect(settings.value(forKey: "sessionLastDay") as? Date == (optionalsKept ? lastDay : nil))
    }

    // MARK: - Helpers

    @discardableResult
    static func insert(
        _ entity: String, _ values: [String: Any], into context: NSManagedObjectContext
    ) -> NSManagedObject {
        let row = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        for (key, value) in values { row.setValue(value, forKey: key) }
        return row
    }

    static func record(_ entity: String, _ id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try #require(try context.fetch(request).first, "No \(entity) \(id)")
    }

    /// The row with `id` in an entry's NDJSON body.
    static func row(_ id: UUID, in body: String?) throws -> [String: Any] {
        let rows = (body ?? "").split(separator: "\n").compactMap { line in
            try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        }
        return try #require(rows.first { $0["id"] as? String == id.uuidString }, "No row \(id)")
    }

    /// The id of an entry's first row.
    static func firstID(in body: String?) throws -> UUID {
        let line = try #require(body?.split(separator: "\n").first, "An empty entry")
        let row = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        return try #require((row["id"] as? String).flatMap(UUID.init(uuidString:)))
    }

    static func loadFixture() throws -> [String: String] {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: "BackupGolden-v46", withExtension: "json"),
            "Missing BackupGolden-v46.json in the test bundle"
        )
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    /// A merge restore of `bodies` (`<store>/<Entity>` → NDJSON), as a backup
    /// of `formatVersion` holds them, into `context`.
    static func merge(
        _ bodies: [String: String], formatVersion: Int, into context: NSManagedObjectContext
    ) async throws {
        let entries: [BackupEntityEntry] = bodies.keys.sorted().compactMap { key in
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let body = bodies[key] else { return nil }
            let rows = body.split(separator: "\n", omittingEmptySubsequences: true).count
            return BackupEntityEntry(entityName: parts[1], storeName: parts[0], count: rows, ndjson: Data(body.utf8))
        }
        let manifest = BackupArchiveManifest(
            formatVersion: formatVersion, createdAt: Date(),
            appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
        )
        let (payload, warnings) = BackupImporter.reconstructPayload(
            from: BackupReader.DecodedBackup(manifest: manifest, entries: entries, preferences: nil)
        )
        #expect(warnings.isEmpty, "The v\(formatVersion) backup decoded with warnings: \(warnings)")
        _ = try await BackupService().importPayload(
            payload: payload,
            envelope: BackupEnvelope(
                formatVersion: formatVersion, encrypted: false, createdAt: Date(),
                fileName: "schema-25", entityCounts: [:]
            ),
            viewContext: context,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )
    }

    /// An entry's rows as sorted-key JSON, sorted, without `dropping`; a string
    /// value that is itself a JSON object (a note's scope) compared by content.
    static func rows(_ body: String, dropping: Set<String> = []) -> [String] {
        body.split(separator: "\n").map { line in
            guard var row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return String(line)
            }
            for field in dropping { row[field] = nil }
            for (field, value) in row {
                guard let text = value as? String, text.hasPrefix("{"),
                      let nested = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
                      let sorted = try? JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys]) else {
                    continue
                }
                row[field] = String(bytes: sorted, encoding: .utf8)
            }
            let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
            let data = (try? JSONSerialization.data(withJSONObject: row, options: options)) ?? Data()
            return String(bytes: data, encoding: .utf8) ?? String(line)
        }
        .sorted()
    }
}
