import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-12, work logging: a closing log with a note files that
/// note once (#36), and a log dated after today happens today (#37).
@Suite("Work log service, bug hunt 2026-10-12")
@MainActor
struct WorkLogServiceFix1012WTests {

    private struct Room {
        let context: NSManagedObjectContext
        let maya = UUID()
        let today = AppCalendar.startOfDay(Date())
        var tomorrow: Date { AppCalendar.addingDays(1, to: today) }
        var inThreeDays: Date { AppCalendar.addingDays(3, to: today) }
    }

    private func makeRoom() throws -> Room {
        Room(context: try CoreDataTestHelpers.makeContext())
    }

    private func seedWork(in room: Room) -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Trinomial cube", studentID: room.maya, lessonID: UUID()
        )
        work.kind = .practiceLesson
        return work
    }

    private func notes(withBody body: String, in context: NSManagedObjectContext) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "body == %@", body)
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    private func completionRecords(
        for work: CDWorkModel, in context: NSManagedObjectContext
    ) -> [CDWorkCompletionRecord] {
        let request = CDFetchRequest(CDWorkCompletionRecord.self)
        request.predicate = NSPredicate(format: "workID == %@", work.id?.uuidString ?? "")
        return context.safeFetch(request)
    }

    // MARK: - #36 One note per log

    @Test("Closing with a note files it once, as the dated work note")
    func closingNoteFiledOnce() throws {
        let room = try makeRoom()
        let work = seedWork(in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        let body = "Needs the trinomial cube again"
        try WorkLogService.log(
            [.init(work: work, status: .keepPracticing, note: body)], on: room.today, context: room.context
        )

        let filed = notes(withBody: body, in: room.context)
        #expect(filed.count == 1, "the note shows once on her Notes tab, not twice")
        #expect(filed.first?.work === work, "the one note is the work's dated note")
        let records = completionRecords(for: work, in: room.context)
        #expect(records.count == 1, "the completion is still recorded")
        #expect(records.allSatisfy { ($0.notes?.count ?? 0) == 0 })
    }

    @Test("Closing without a note files no note")
    func closingWithoutNoteFilesNone() throws {
        let room = try makeRoom()
        let work = seedWork(in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        try WorkLogService.log([.init(work: work, status: .mastered)], on: room.today, context: room.context)

        let request = CDFetchRequest(CDNote.self)
        #expect(room.context.safeFetch(request).isEmpty)
        #expect(completionRecords(for: work, in: room.context).count == 1)
    }

    // MARK: - #37 A later day is logged as today

    @Test("Closing on a pill dated later this week finishes the work today")
    func closingOnLaterDayFinishesToday() throws {
        let room = try makeRoom()
        let work = seedWork(in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        let body = "Built it without the box lid"
        try WorkLogService.log(
            [.init(work: work, status: .mastered, note: body)], on: room.inThreeDays, context: room.context
        )

        #expect(work.completedAt == room.today, "not the pill's day, which hasn't come yet")
        let records = completionRecords(for: work, in: room.context)
        #expect(records.map(\.completedAt) == [room.today])
        let note = try #require(notes(withBody: body, in: room.context).first)
        let created = try #require(note.createdAt)
        #expect(AppCalendar.isSameDay(created, room.today), "the note is dated the day it was written")
    }

    @Test("Keep Working on a later pill doesn't complete the check-ins before it")
    func seenOnLaterDayLeavesLaterCheckIns() throws {
        let room = try makeRoom()
        let work = seedWork(in: room)
        let tomorrows = CDWorkCheckIn.make(for: work, on: room.tomorrow, purpose: "progressCheck", in: room.context)
        let pills = CDWorkCheckIn.make(for: work, on: room.inThreeDays, purpose: "progressCheck", in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let receipt = try WorkLogService.log(
            [.init(work: work, status: nil)], on: room.inThreeDays, context: room.context
        )

        #expect(tomorrows.status == .scheduled, "tomorrow's check hasn't happened")
        #expect(pills.status == .scheduled, "nor has the pill's own day")
        #expect(receipt.checkInsSettled == 0)
    }

    @Test("A past day still logs on that day")
    func pastDayStillLogs() throws {
        let room = try makeRoom()
        let work = seedWork(in: room)
        let yesterday = AppCalendar.addingDays(-1, to: room.today)
        #expect(CoreDataTestHelpers.save(room.context))

        try WorkLogService.log([.init(work: work, status: .mastered)], on: yesterday, context: room.context)

        #expect(work.completedAt == yesterday)
    }
}
