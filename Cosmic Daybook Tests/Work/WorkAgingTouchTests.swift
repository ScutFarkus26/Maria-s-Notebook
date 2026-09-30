import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Logic-break sweep 2026-09-29, E7: the "most recent meaningful touch" took
// the first kind of touch that existed, not the latest, so an old check-in
// hid yesterday's note and the work read as stale.
@Suite("Work aging: last touch")
@MainActor
struct WorkAgingTouchTests {

    @Test("The latest touch of any kind counts, not the first kind that exists")
    func latestTouchWins() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        work.id = UUID()
        work.assignedAt = AppCalendar.addingDays(-60, to: Date())
        work.lastTouchedAt = AppCalendar.addingDays(-40, to: Date())

        let checkIn = CDWorkCheckIn(context: context)
        checkIn.date = AppCalendar.addingDays(-30, to: Date())
        checkIn.status = .completed
        let note = CDNote(context: context)
        note.body = "Carried the bead frame to a friend and taught her."
        note.createdAt = AppCalendar.addingDays(-1, to: Date())
        note.updatedAt = note.createdAt

        let touch = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: [checkIn], notes: [note])
        #expect(touch == AppCalendar.startOfDay(AppCalendar.addingDays(-1, to: Date())))

        // An explicit touch still counts when it is the latest.
        work.lastTouchedAt = Date()
        #expect(WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: [checkIn], notes: [note])
            == AppCalendar.startOfDay(Date()))

        // Nothing at all: the day it was assigned.
        work.lastTouchedAt = nil
        #expect(WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: [], notes: [])
            == AppCalendar.startOfDay(AppCalendar.addingDays(-60, to: Date())))
    }
}
