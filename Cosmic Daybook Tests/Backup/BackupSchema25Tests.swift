import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Schema 25's fields and its one new type through the backup (format 47,
/// plan "Domain logic fixes", Phase 1): which assignment a work copy is of and
/// whether it is the shared row, a child's own three flags on her
/// presentation record, the person a guardian row stands for, the classroom's
/// time zone and session days, and the children's level history.
///
/// Each is written and restored as set, on a new record and over one already
/// here, and an unset flag stays apart from a false one. A format-46 backup
/// (`BackupGolden-v46.json`: the golden reference as main wrote it at format
/// 46) restores every record with all of them unset, and merged over records
/// that have them leaves them as they were.
@Suite("Backup: schema 25's fields (format 47)", .serialized)
@MainActor
struct BackupSchema25Tests {
    final class BundleToken {}

    let workID = UUID()
    let assignmentID = UUID()
    let setPresentationID = UUID()
    let unsetPresentationID = UUID()
    let guardianID = UUID()
    let personID = UUID()
    let settingsID = UUID()
    let levelChangeID = UUID()
    let studentID = UUID()
    // Whole seconds: the backup writes milliseconds.
    let firstDay = Date(timeIntervalSinceReferenceDate: 810_000_000)
    let lastDay = Date(timeIntervalSinceReferenceDate: 835_000_000)
    let changedOn = Date(timeIntervalSinceReferenceDate: 815_000_000)
    let stamped = Date(timeIntervalSinceReferenceDate: 815_000_100)

    // MARK: - Format 47

    @Test("Every schema-25 field and level change is written, and restores as set into a new store")
    func newFieldsRoundTrip() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        seedSchema25Records(into: source)
        #expect(CoreDataTestHelpers.save(source), "Fixture save failed")
        let bodies = try BackupGoldenOutputTests.export(source)

        // Written: a set flag, false included; an unset one is left out.
        let work = try Self.row(workID, in: bodies["private/WorkModel"])
        #expect(work["assignmentID"] as? String == assignmentID.uuidString)
        #expect(work["isSharedRow"] as? Bool == true)
        let set = try Self.row(setPresentationID, in: bodies["private/LessonPresentation"])
        #expect(set["needsPractice"] as? Bool == true)
        #expect(set["needsAnotherPresentation"] as? Bool == false)
        #expect(set["manuallyUnblocked"] as? Bool == true)
        let unset = try Self.row(unsetPresentationID, in: bodies["private/LessonPresentation"])
        for key in ["needsPractice", "needsAnotherPresentation", "manuallyUnblocked"] {
            #expect(unset[key] == nil, "an unset \(key) was written")
        }
        #expect(try Self.row(guardianID, in: bodies["private/Guardian"])["personID"] as? String == personID.uuidString)
        let settings = try Self.row(settingsID, in: bodies["shared/AttendanceEmailSettings"])
        #expect(settings["classroomTimeZoneID"] as? String == "America/Chicago")
        #expect(settings["sessionFirstDay"] != nil && settings["sessionLastDay"] != nil)
        let change = try Self.row(levelChangeID, in: bodies["private/LevelChange"])
        #expect(change["fromLevelRaw"] as? String == "Lower" && change["toLevelRaw"] as? String == "Upper")

        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await Self.merge(bodies, formatVersion: BackupWriter.formatVersion, into: target)
        // The restore leaves nothing unsaved, so its after-restore fills run.
        #expect(!target.hasChanges)
        try expectSchema25Values(in: target)
    }

    @Test("A format-47 backup's fields replace a record's own on a merge")
    func newFieldsOverwriteOnMerge() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        seedSchema25Records(into: source)
        #expect(CoreDataTestHelpers.save(source), "Fixture save failed")
        let bodies = try BackupGoldenOutputTests.export(source)

        // The same records here, every new field holding something else.
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        seedSchema25Records(into: target)
        let work = try Self.record("WorkModel", workID, in: target)
        work.setValue(UUID().uuidString, forKey: "assignmentID")
        work.setValue(false, forKey: "isSharedRow")
        let set = try Self.record("LessonPresentation", setPresentationID, in: target)
        set.setValue(false, forKey: "needsPractice")
        set.setValue(true, forKey: "needsAnotherPresentation")
        set.setValue(nil, forKey: "manuallyUnblocked")
        let unset = try Self.record("LessonPresentation", unsetPresentationID, in: target)
        unset.setValue(true, forKey: "needsPractice")
        try Self.record("Guardian", guardianID, in: target).setValue(UUID().uuidString, forKey: "personID")
        let settings = try Self.record("AttendanceEmailSettings", settingsID, in: target)
        settings.setValue("Europe/London", forKey: "classroomTimeZoneID")
        settings.setValue(nil, forKey: "sessionLastDay")
        let change = try Self.record("LevelChange", levelChangeID, in: target)
        change.setValue("Adolescent", forKey: "toLevelRaw")
        #expect(CoreDataTestHelpers.save(target), "Target save failed")

        try await Self.merge(bodies, formatVersion: BackupWriter.formatVersion, into: target)
        try expectSchema25Values(in: target)
    }

    // MARK: - Format 46

    @Test("A format-46 backup restores every record, field for field, with schema 25's fields unset")
    func format46BackupRestores() async throws {
        let v46 = try Self.loadFixture()
        #expect(v46["private/LevelChange"] == nil)
        #expect(v46["private/WorkModel"]?.contains(#""isSharedRow""#) == false)

        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await Self.merge(v46, formatVersion: 46, into: target)

        let work = try Self.record("WorkModel", try Self.firstID(in: v46["private/WorkModel"]), in: target)
        #expect(work.value(forKey: "assignmentID") == nil)
        #expect(work.value(forKey: "isSharedRow") as? Bool == false)
        let presentation = try Self.record(
            "LessonPresentation", try Self.firstID(in: v46["private/LessonPresentation"]), in: target
        )
        for key in ["needsPractice", "needsAnotherPresentation", "manuallyUnblocked"] {
            #expect(presentation.value(forKey: key) == nil, "\(key) is set")
        }
        let guardian = try Self.record("Guardian", try Self.firstID(in: v46["private/Guardian"]), in: target)
        #expect(guardian.value(forKey: "personID") == nil)
        let settings = try Self.record(
            "AttendanceEmailSettings", try Self.firstID(in: v46["shared/AttendanceEmailSettings"]), in: target
        )
        for key in ["classroomTimeZoneID", "sessionFirstDay", "sessionLastDay"] {
            #expect(settings.value(forKey: key) == nil, "\(key) is set")
        }
        #expect(try target.count(for: NSFetchRequest<NSManagedObject>(entityName: "LevelChange")) == 0)

        // Backed up again, it is the same backup but for the work flag every
        // record now writes and the attendance pair every restore tidies.
        // Types a restore leaves alone come back out only if the store had them.
        let reexported = try BackupGoldenOutputTests.export(target)
        let expected = BackupGoldenOutputTests.asRestored(v46.filter { key, _ in
            !BackupEntityRegistry.keptOnRestoreEntityNames.contains(String(key.split(separator: "/").last ?? ""))
        })
        #expect(Set(reexported.keys) == Set(expected.keys))
        for (key, body) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(
                Self.rows(reexported[key] ?? "", dropping: ["isSharedRow"]) == Self.rows(body),
                "\(key) came back different"
            )
        }
    }

    @Test("A format-46 backup merged over records that have schema 25's fields leaves them as they were")
    func format46MergeKeepsRecordsOwn() async throws {
        let v46 = try Self.loadFixture()
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await Self.merge(v46, formatVersion: 46, into: target)
        let ids = Fixture46IDs(
            work: try Self.firstID(in: v46["private/WorkModel"]),
            presentation: try Self.firstID(in: v46["private/LessonPresentation"]),
            guardian: try Self.firstID(in: v46["private/Guardian"]),
            settings: try Self.firstID(in: v46["shared/AttendanceEmailSettings"])
        )
        try setSchema25Fields(on: ids, in: target)
        #expect(CoreDataTestHelpers.save(target), "Save failed")

        try await Self.merge(v46, formatVersion: 46, into: target)
        try expectSchema25Fields(on: ids, in: target, optionalsKept: true)

        // Not vacuous: the same rows under a format-47 header say each
        // optional field is unset, and the merge clears it. The work flag
        // isn't optional, so a row without it still leaves the record's own.
        try await Self.merge(v46, formatVersion: BackupWriter.formatVersion, into: target)
        try expectSchema25Fields(on: ids, in: target, optionalsKept: false)
    }
}
