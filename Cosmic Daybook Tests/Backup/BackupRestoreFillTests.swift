import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The steps every restore runs once its records are saved
/// (`BackupService.runAfterRestoreFills`): the attendance tidy-up, and the
/// work assignment fill and guardian person fill that later phases of plan
/// "Domain logic fixes" add to its list. Each runs in order and is saved once;
/// none runs while the notebook holds someone else's unsaved change.
@Suite("Backup: after-restore fills")
@MainActor
struct BackupRestoreFillTests {
    private let guardianID = UUID()
    private let personID = UUID()
    private let studentID = UUID()

    @MainActor
    private final class FillLog {
        var calls: [String] = []
    }

    @Test("The after-restore fills run in order with the backup's format, and what they change is saved")
    func fillsRunAndSave() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        BackupSchema25Tests.insert(
            "Guardian", ["id": guardianID, "studentID": studentID.uuidString, "name": "A Parent"], into: context
        )
        #expect(CoreDataTestHelpers.save(context), "Fixture save failed")

        let log = FillLog()
        let person = personID.uuidString
        let fills = [
            BackupRestoreFill(name: "person") { context, version in
                log.calls.append("person \(version)")
                let request = NSFetchRequest<NSManagedObject>(entityName: "Guardian")
                for guardian in (try? context.fetch(request)) ?? [] where guardian.value(forKey: "personID") == nil {
                    guardian.setValue(person, forKey: "personID")
                }
            },
            BackupRestoreFill(name: "second") { _, version in log.calls.append("second \(version)") }
        ]
        #expect(BackupService().runAfterRestoreFills(fills, formatVersion: 46, in: context))
        #expect(log.calls == ["person 46", "second 46"])
        #expect(!context.hasChanges, "the fills' change wasn't saved")
        context.refreshAllObjects()
        let guardian = try BackupSchema25Tests.record("Guardian", guardianID, in: context)
        #expect(guardian.value(forKey: "personID") as? String == person)
    }

    @Test("The after-restore fills don't run while the notebook holds an unsaved change")
    func fillsWaitForUnsavedChange() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        BackupSchema25Tests.insert("Guardian", ["id": guardianID, "studentID": studentID.uuidString], into: context)
        let log = FillLog()
        let fills = [BackupRestoreFill(name: "log") { _, _ in log.calls.append("ran") }]
        #expect(!BackupService().runAfterRestoreFills(fills, formatVersion: 47, in: context))
        #expect(log.calls.isEmpty)
        #expect(context.hasChanges, "someone else's unsaved change was saved or dropped")
        #expect(BackupService().runAfterRestoreFills([], formatVersion: 47, in: context), "no fills is nothing to do")
    }

    @Test("A restore puts an attendance mark's odd pair right, keeps the pairs that fit, and leaves change times alone")
    func restoreTidiesAttendancePairs() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: source, firstName: "Maya", lastName: "Stone")
        let stamped = Date(timeIntervalSinceReferenceDate: 815_000_100)
        func mark(_ status: AttendanceStatus, dayOffset: Int) throws -> (CDAttendanceRecord, UUID) {
            let mark = CDAttendanceRecord(context: source)
            mark.studentID = maya.cloudKitKey
            mark.date = AppCalendar.addingDays(dayOffset, to: AppCalendar.startOfDay(stamped))
            mark.statusRaw = status.rawValue
            mark.modifiedAt = stamped
            return (mark, try #require(mark.id))
        }
        // Present with an old "Sick" and a left-from status: odd.
        let (odd, oddID) = try mark(.present, dayOffset: 0)
        odd.absenceReasonRaw = AbsenceReason.sick.rawValue
        odd.statusBeforeLeavingRaw = AttendanceStatus.tardy.rawValue
        // An absence with its reason, and a Left Early from late: both fit.
        let (sick, sickID) = try mark(.absent, dayOffset: 1)
        sick.absenceReasonRaw = AbsenceReason.sick.rawValue
        let (left, leftID) = try mark(.leftEarly, dayOffset: 2)
        left.statusBeforeLeavingRaw = AttendanceStatus.tardy.rawValue
        left.leftAt = stamped
        #expect(CoreDataTestHelpers.save(source), "Fixture save failed")
        let bodies = try BackupGoldenOutputTests.export(source)
        let row = try BackupSchema25Tests.row(oddID, in: bodies["shared/AttendanceRecord"])
        #expect(row["absenceReason"] as? String == AbsenceReason.sick.rawValue, "the backup keeps the mark as it was")

        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await BackupSchema25Tests.merge(bodies, formatVersion: BackupWriter.formatVersion, into: target)
        #expect(!target.hasChanges, "the tidy-up wasn't saved")
        target.refreshAllObjects()
        let marks = target.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        let restored = Dictionary(
            marks.compactMap { record in record.id.map { ($0, record) } }, uniquingKeysWith: { first, _ in first }
        )
        #expect(restored.count == 3)
        let tidied = try #require(restored[oddID])
        #expect(tidied.status == .present)
        #expect(tidied.absenceReason == .none)
        #expect(tidied.statusBeforeLeavingRaw == nil)
        #expect(try #require(restored[sickID]).absenceReason == .sick)
        let leftEarly = try #require(restored[leftID])
        #expect(leftEarly.statusBeforeLeavingRaw == AttendanceStatus.tardy.rawValue)
        #expect(leftEarly.leftAt == stamped)
        #expect(restored.values.allSatisfy { $0.modifiedAt == stamped }, "the tidy-up is no one's change")
    }
}
