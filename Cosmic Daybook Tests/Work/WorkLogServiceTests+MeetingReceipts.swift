import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// A log's receipt kept with a meeting draft as URIs and plain values
// (`MeetingCloseToken`, bug hunt 2026-10-09, #9): read back after a JSON
// round trip it undoes like the original, and it refuses a row changed since.
extension WorkLogServiceTests {

    /// One child's work row with her participant row.
    private struct ReceiptRoom {
        let context: NSManagedObjectContext
        let work: CDWorkModel
        let child: UUID
    }

    @MainActor
    private func receiptRoom() throws -> ReceiptRoom {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let child = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame", studentID: child)
        let participant = CDWorkParticipantEntity(context: context)
        participant.id = UUID()
        participant.studentID = child.uuidString
        participant.work = work
        return ReceiptRoom(context: context, work: work, child: child)
    }

    @Test("A receipt kept as plain values with a meeting draft undoes like the original")
    @MainActor
    func storedReceiptUndoes() throws {
        let room = try receiptRoom()
        let (context, work, child) = (room.context, room.work, room.child)
        let today = AppCalendar.startOfDay(Date())
        let todays = CDWorkCheckIn.make(for: work, on: today, purpose: "progressCheck", in: context)
        let later = CDWorkCheckIn.make(
            for: work, on: AppCalendar.addingDays(7, to: today), purpose: "progressCheck", in: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let receipt = try WorkLogService.log(
            [.init(work: work, status: .incomplete, note: "Needs another go")], on: today, context: context
        )
        let kept = try #require(MeetingCloseToken(receipt.token, leaving: work, in: context))
        let stored = try JSONDecoder().decode(MeetingCloseToken.self, from: JSONEncoder().encode(kept))
        #expect(stored == kept)

        #expect(MeetingCloseToken.takeBack([stored], of: work, in: context) == .takenBack)
        #expect(context.safeSave())
        #expect(work.status == .active)
        #expect(work.completedAt == nil)
        #expect(work.participant(for: child)?.completedAt == nil)
        #expect(todays.status == .scheduled)
        #expect(later.status == .scheduled)
        #expect(try WorkCompletionService.records(for: try #require(work.id), in: context).isEmpty)
        let remainingNotes = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
        #expect(remainingNotes.isEmpty)
    }

    @Test("A kept receipt refuses to undo a row changed after it, and changes nothing")
    @MainActor
    func storedReceiptRefusesLaterChange() throws {
        let room = try receiptRoom()
        let (context, work) = (room.context, room.work)
        #expect(CoreDataTestHelpers.save(context))
        let receipt = try WorkLogService.log([.init(work: work, status: .incomplete)], context: context)
        let kept = try #require(MeetingCloseToken(receipt.token, leaving: work, in: context))

        try WorkLogService.log([.init(work: work, status: .mastered)], context: context)
        #expect(MeetingCloseToken.takeBack([kept], of: work, in: context) == .changedSince)
        #expect(work.status == .mastered)
        #expect(!context.hasChanges)
    }
}
