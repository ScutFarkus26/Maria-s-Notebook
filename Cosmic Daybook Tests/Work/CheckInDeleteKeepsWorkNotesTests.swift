import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #6. A note logged on a work row also hangs on
// that day's check-in (`WorkLogService.addNote`), and a check-in's `notes`
// cascade. Deleting the check-in (the work detail's delete, the launch orphan
// repair, a delete arriving from another device) took the work's note with
// it. Before it goes, a check-in now lets go of the notes that also belong to
// its work; its own notes still go with it.

@Suite("Deleting a check-in keeps the work's notes")
@MainActor
struct CheckInDeleteKeepsWorkNotesTests {

    private func bodies(in context: NSManagedObjectContext) -> Set<String> {
        Set(context.safeFetch(CDFetchRequest(CDNote.self)).map(\.body))
    }

    private func note(
        _ body: String, work: CDWorkModel?, checkIn: CDWorkCheckIn?, in context: NSManagedObjectContext
    ) -> CDNote {
        let note = CoreDataTestHelpers.seedNote(in: context, body: body)
        note.work = work
        note.workCheckIn = checkIn
        return note
    }

    @Test("A note on both the work and the check-in stays on the work; the check-in's own note goes")
    func workNoteSurvivesCheckInDelete() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), in: context)
        let shared = note("Carried the tubes to a thousand", work: work, checkIn: checkIn, in: context)
        _ = note("Moved to Thursday", work: nil, checkIn: checkIn, in: context)
        #expect(CoreDataTestHelpers.save(context))

        context.delete(checkIn)
        #expect(CoreDataTestHelpers.save(context))

        #expect(bodies(in: context) == ["Carried the tubes to a thousand"])
        #expect(shared.work === work)
        #expect(shared.workCheckIn == nil)
        #expect((work.unifiedNotes?.count ?? 0) == 1)
    }

    @Test("A note logged on the work keeps its place there when the day's check-in is deleted")
    func loggedNoteSurvivesCheckInDelete() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame")
        let today = AppCalendar.startOfDay(Date())
        let checkIn = CDWorkCheckIn.make(for: work, on: today, purpose: "progressCheck", in: context)
        #expect(CoreDataTestHelpers.save(context))
        try WorkLogService.log(
            [.init(work: work, note: "Lost her place at the hundreds")],
            on: today, context: context
        )
        let logged = try #require(context.safeFetch(CDFetchRequest(CDNote.self)).first)
        #expect(logged.workCheckIn === checkIn)

        context.delete(checkIn)
        #expect(CoreDataTestHelpers.save(context))

        #expect(bodies(in: context) == ["Lost her place at the hundreds"])
        #expect(logged.work === work)
    }

    @Test("A delete made on another context (as a sync import makes it) keeps the work's note too")
    func deleteOnAnotherContextKeepsWorkNote() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let view = stack.viewContext
        let work = CoreDataTestHelpers.seedWorkModel(in: view, title: "Checkerboard")
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), in: view)
        _ = note("Needs the long multiplication card", work: work, checkIn: checkIn, in: view)
        #expect(CoreDataTestHelpers.save(view))
        let checkInID = checkIn.objectID

        let background = stack.newBackgroundContext()
        let saved = await background.perform {
            background.delete(background.object(with: checkInID))
            return background.safeSave()
        }
        #expect(saved)

        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = view.persistentStoreCoordinator
        let notes = reader.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.map(\.body) == ["Needs the long multiplication card"])
        #expect(notes.first?.work?.title == "Checkerboard")
        #expect(reader.safeFetch(CDFetchRequest(CDWorkCheckIn.self)).isEmpty)
    }

    @Test("Deleting the work still takes every note, the check-in's included")
    func deletingWorkTakesEveryNote() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), in: context)
        _ = note("On the work and the check-in", work: work, checkIn: checkIn, in: context)
        _ = note("On the check-in only", work: nil, checkIn: checkIn, in: context)
        _ = note("On the work only", work: work, checkIn: nil, in: context)
        #expect(CoreDataTestHelpers.save(context))

        context.delete(work)
        #expect(CoreDataTestHelpers.save(context))

        #expect(bodies(in: context).isEmpty)
        #expect(context.safeFetch(CDFetchRequest(CDWorkCheckIn.self)).isEmpty)
    }
}
