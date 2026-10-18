// Bug hunt 2026-10-17 review (a1), #2 of St #30: earlier builds copied real
// reminders and calendar events into the Sample Class's practice store, and
// Today there kept listing them, frozen. The seeder makes neither, and the
// practice store never syncs, so preparing it clears them.

import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Sample Class clears copied reminders and events (Fix1017ReviewA1)", .serialized)
@MainActor
struct SampleClassroomFix1017ReviewA1Tests {

    @Test("Preparing the Sample Class deletes reminders and calendar events left in it")
    func clearsCopiedRows() throws {
        let primary = try CoreDataTestHelpers.makeInMemoryStack()
        let sample = try CoreDataTestHelpers.makeInMemoryStack()
        let context = sample.viewContext

        let reminder = CDReminder(context: context)
        reminder.id = UUID()
        reminder.title = "Call the office"
        reminder.eventKitCalendarID = "real-list"
        let event = CDCalendarEvent(context: context)
        event.id = UUID()
        event.title = "Staff meeting"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(3600)
        try context.save()

        try SampleClassroomSeeder.prepare(lessonsFrom: primary.viewContext, sampleContext: context)

        #expect(try context.count(for: CDFetchRequest(CDReminder.self)) == 0)
        #expect(try context.count(for: CDFetchRequest(CDCalendarEvent.self)) == 0)
    }
}
