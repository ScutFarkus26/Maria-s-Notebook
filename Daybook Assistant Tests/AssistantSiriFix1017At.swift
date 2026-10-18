import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Bug hunt 2026-10-17, #1 and #5, in the Assistant (it compiles
// `SiriAttendance` and `CDAttendanceStore` by path). In `AssistantSiriTests`,
// so they run one at a time with it: Siri's undo memory and the Late memory
// are the app's own standard-defaults keys. On a Tuesday the suite's other
// tests don't use.
extension AssistantSiriTests {

    private static let fixDay = "2031-01-07"

    private static func fixSiri(_ stack: CoreDataStack, on day: Date) -> SiriAttendance {
        SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
    }

    @Test("Here on a child who left early brings her back in class, with her arrival and trip")
    func hereOnLeftEarlyIsBackInClassHere() async throws {
        let day = try AssistantTestSupport.day(Self.fixDay)
        defer { SiriAttendanceChange.forget() }
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        _ = context.safeSave()
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.ensureRecord(for: maya, on: day))
        store.updateStatus(record, to: .present)
        store.updateStatus(record, to: .leftEarly)
        let arrived = day.addingTimeInterval(8 * 3_600 + 2 * 60)
        let left = day.addingTimeInterval(10 * 3_600 + 15 * 60)
        record.markedAt = arrived
        record.leftAt = left
        #expect(context.safeSave())

        let siri = Self.fixSiri(stack, on: day)
        #expect(try await siri.markHere(maya) == (.leftEarly, .present))
        #expect(record.status == .present)
        #expect(record.markedAt == arrived)
        #expect(record.leftAt == left)

        _ = try await siri.undoLast()
        #expect(record.status == .leftEarly)
        #expect(record.markedAt == arrived)
    }

    @Test("An absence's reason goes when she's marked here")
    func reasonGoesWhenMarkedHere() async throws {
        let day = try AssistantTestSupport.day(Self.fixDay)
        defer { SiriAttendanceChange.forget() }
        let stack = try AssistantTestSupport.makeStack()
        let maya = AssistantTestSupport.student("Maya", "Stone", in: stack.viewContext)
        _ = stack.viewContext.safeSave()
        let siri = Self.fixSiri(stack, on: day)

        try await siri.mark(maya, as: .absent, reason: .vacation)
        _ = try await siri.markHere(maya)
        try await siri.mark(maya, as: .absent)
        let record = try #require(try siri.store.loadRecords(for: day).first)
        #expect(record.status == .absent)
        #expect(record.absenceReasonRaw == AbsenceReason.none.rawValue)
    }
}
