import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #2, #8–#11, #16. What a child's Notes tab shows:
// group notes through their links (once, and only while the note still
// names her), notes on shared work for every participant, dates by when a
// note was written, plain labels, project-session notes only for members,
// and Writing Help drafting from the same notes within the school year.

@Suite("Student Notes tab (Fix1010E1)")
@MainActor
struct StudentNotesTabTests {

    private struct Class {
        let context: NSManagedObjectContext
        let etty: CDStudent
        let ora: CDStudent
        let tiffy: CDStudent
    }

    private func makeClass() throws -> Class {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let tiffy = CoreDataTestHelpers.seedStudent(in: context, firstName: "Tiferet", lastName: "Pardo")
        #expect(CoreDataTestHelpers.save(context))
        return Class(context: context, etty: etty, ora: ora, tiffy: tiffy)
    }

    private func tab(for student: CDStudent, in context: NSManagedObjectContext) -> StudentNotesViewModel {
        StudentNotesViewModel(student: student, viewContext: context, saveCoordinator: .preview)
    }

    private func link(_ note: CDNote, to student: CDStudent, in context: NSManagedObjectContext) {
        let link = CDNoteStudentLink(context: context)
        link.noteID = note.id?.uuidString ?? ""
        link.studentID = student.id?.uuidString ?? ""
        link.note = note
    }

    @Test("A group note shows once on each child's tab, even linked twice, and not after she's taken off")
    func groupNoteThroughLinks() throws {
        let room = try makeClass()
        let ettyID = try #require(room.etty.id)
        let oraID = try #require(room.ora.id)
        let note = CoreDataTestHelpers.seedNote(in: room.context, body: "Built the cube together.")
        note.scope = .students([ettyID, oraID])
        link(note, to: room.etty, in: room.context)
        link(note, to: room.etty, in: room.context)  // a double from two devices
        link(note, to: room.ora, in: room.context)
        link(note, to: room.tiffy, in: room.context)  // stale: the scope doesn't name her
        #expect(CoreDataTestHelpers.save(room.context))
        let noteID = try #require(note.id)

        #expect(tab(for: room.etty, in: room.context).items.filter { $0.id == noteID }.count == 1)
        #expect(tab(for: room.ora, in: room.context).items.contains { $0.id == noteID })
        #expect(!tab(for: room.tiffy, in: room.context).items.contains { $0.id == noteID })
    }

    @Test("A note on a shared work row shows on every participant's tab")
    func sharedWorkNotes() throws {
        let room = try makeClass()
        let ettyID = try #require(room.etty.id)
        let oraID = try #require(room.ora.id)
        let work = CoreDataTestHelpers.seedWorkModel(in: room.context, title: "Bead chains", studentID: ettyID)
        for student in [ettyID, oraID] {
            let participant = CDWorkParticipantEntity(context: room.context)
            participant.studentID = student.uuidString
            participant.work = work
        }
        let shared = CoreDataTestHelpers.seedNote(in: room.context, body: "They counted the 7 chain.")
        shared.scope = .all
        shared.work = work
        let ettyOnly = CoreDataTestHelpers.seedNote(in: room.context, body: "Etty skip-counted alone.")
        ettyOnly.scope = .student(ettyID)
        ettyOnly.work = work
        #expect(CoreDataTestHelpers.save(room.context))

        let oraItems = tab(for: room.ora, in: room.context).items
        #expect(oraItems.contains { $0.id == shared.id })
        #expect(!oraItems.contains { $0.id == ettyOnly.id }, "a note about Etty alone isn't Ora's")
        let ettyItems = tab(for: room.etty, in: room.context).items
        #expect(ettyItems.contains { $0.id == shared.id })
        #expect(ettyItems.contains { $0.id == ettyOnly.id })
        #expect(!tab(for: room.tiffy, in: room.context).items.contains { $0.id == shared.id })
    }

    @Test("Notes are dated when written, not when last touched")
    func datedByCreation() throws {
        let room = try makeClass()
        let written = try CoreDataTestHelpers.day("2026-09-01")
        let note = CoreDataTestHelpers.seedNote(in: room.context, body: "First week.")
        note.scope = .student(try #require(room.etty.id))
        note.createdAt = written
        note.updatedAt = Date()  // pinned today
        note.isPinned = true
        #expect(CoreDataTestHelpers.save(room.context))

        let item = try #require(tab(for: room.etty, in: room.context).items.first { $0.id == note.id })
        #expect(item.date == written)
    }

    @Test("A check-in's note says so, and an old field note reads as the guide's")
    func labels() throws {
        let room = try makeClass()
        let ettyID = try #require(room.etty.id)
        let work = CoreDataTestHelpers.seedWorkModel(in: room.context, title: "Stamp game", studentID: ettyID)
        let checkIn = CDWorkCheckIn(context: room.context)
        checkIn.work = work
        checkIn.workID = work.id?.uuidString ?? ""
        #expect(checkIn.setLegacyNoteText("Carried tens on her own.", in: room.context))
        #expect(CoreDataTestHelpers.save(room.context))

        let items = tab(for: room.etty, in: room.context).items
        let item = try #require(items.first { $0.body == "Carried tens on her own." })
        #expect(item.contextText == "Check-In: Stamp game")
        #expect(item.reportedBy == LegacyNoteFieldConstants.reporter)
    }

    @Test("A whole-class project session note shows only to the project's members")
    func projectSessionNotes() throws {
        let room = try makeClass()
        let project = CDProject(context: room.context)
        project.title = "Book club"
        project.memberStudentUUIDs = [try #require(room.etty.id)]
        let session = CDProjectSession(context: room.context)
        session.project = project
        // Written before 2026-10-10: scoped to the whole class.
        let note = CoreDataTestHelpers.seedNote(in: room.context, body: "Chapter 3 discussion.")
        note.scope = .all
        note.reportedBy = LegacyNoteFieldConstants.reporter
        note.projectSession = session
        #expect(CoreDataTestHelpers.save(room.context))

        let ettyItem = tab(for: room.etty, in: room.context).items.first { $0.id == note.id }
        #expect(ettyItem?.contextText == "Book club")
        #expect(!tab(for: room.ora, in: room.context).items.contains { $0.id == note.id })
    }

    @Test("The quick bar's note saves, and a failed save adds nothing")
    func quickBar() throws {
        let room = try makeClass()
        let model = tab(for: room.etty, in: room.context)
        #expect(model.addGeneralNote(body: "Asked for the checkerboard."))
        #expect(!room.context.hasChanges)
        #expect(model.items.contains { $0.body == "Asked for the checkerboard." })

        let unsavable = try QuickNoteSaveTests.unsavableContext()
        let student = CoreDataTestHelpers.seedStudent(in: unsavable, firstName: "Etty", lastName: "Dechter")
        let failing = StudentNotesViewModel(student: student, viewContext: unsavable, saveCoordinator: .preview)
        #expect(!failing.addGeneralNote(body: "Lost?"))
        #expect(!QuickNoteSaveTests.hasUnsavedNote(in: unsavable))
    }

    @Test("Writing Help drafts from the tab's notes in the school year, group notes included")
    func writingHelpNotes() throws {
        let room = try makeClass()
        let ettyID = try #require(room.etty.id)
        let oraID = try #require(room.ora.id)
        let group = CoreDataTestHelpers.seedNote(in: room.context, body: "Group lesson on fractions.")
        group.scope = .students([ettyID, oraID])
        group.syncStudentLinks(in: room.context)
        group.createdAt = try CoreDataTestHelpers.day("2026-09-15")
        let lastYear = CoreDataTestHelpers.seedNote(in: room.context, body: "Last spring.")
        lastYear.scope = .student(ettyID)
        lastYear.createdAt = try CoreDataTestHelpers.day("2026-04-01")
        let meeting = CDStudentMeeting(context: room.context)
        meeting.studentID = ettyID.uuidString
        meeting.date = try CoreDataTestHelpers.day("2026-09-20")
        meeting.reflection = "Wants more art."
        #expect(CoreDataTestHelpers.save(room.context))

        let year = DateRange(
            start: try CoreDataTestHelpers.day("2026-08-25"), end: try CoreDataTestHelpers.day("2027-08-25")
        )
        let notes = tab(for: room.etty, in: room.context).writingHelpNotes(in: year)
        #expect(notes.map(\.body) == ["Group lesson on fractions."])
    }
}
