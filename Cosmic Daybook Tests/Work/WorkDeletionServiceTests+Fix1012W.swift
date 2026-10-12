import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-12 #44: "Delete this work?" counts every note that goes
/// with the work — its own, its check-ins' and its completion records' — and
/// a note filed on both the work and a check-in once.
@Suite("Work deletion, bug hunt 2026-10-12")
@MainActor
struct WorkDeletionFix1012WTests {

    @Test("The delete count includes check-in and completion notes, each note once")
    func cascadeCountsEveryNote() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Pin map of Africa", studentID: maya)
        let workID = try #require(work.id)
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), purpose: "progressCheck", in: context)
        #expect(CoreDataTestHelpers.save(context))

        // The work's own field note.
        work.setLegacyNoteText("Find the capitals first", in: context)
        // A check-in's own note.
        checkIn.setLegacyNoteText("Labeled the north half", in: context)
        // A logged note lands on the work and on that day's check-in: one note.
        WorkLogService.addNote("Finished the south half", to: work, on: Date(), in: context)
        // A completion record's note.
        try WorkCompletionService.markCompleted(
            workID: workID, studentID: maya, note: "Done without the key", in: context, saveImmediately: false
        )
        #expect(CoreDataTestHelpers.save(context))

        let cascade = WorkDeletionService(context: context).cascade(for: work)

        #expect(cascade.observations == 4)
        #expect(cascade.checkIns == 1)
        #expect(cascade.completionRecords == 1)
    }

    @Test("Empty notes aren't counted")
    func emptyNotesNotCounted() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Pin map of Africa")
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), purpose: "progressCheck", in: context)
        let blank = CDNote(context: context)
        blank.body = "  "
        blank.workCheckIn = checkIn
        #expect(CoreDataTestHelpers.save(context))

        #expect(WorkDeletionService(context: context).cascade(for: work).observations == 0)
    }
}
