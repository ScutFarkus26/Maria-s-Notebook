import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-12 #40: a check-in note on one child's linked copy is
/// about that child, as `WorkLogService` scopes a logged note; a genuinely
/// shared row's check-in note is about everyone on it.
@Suite("Check-in note scope, bug hunt 2026-10-12")
@MainActor
struct CheckInNoteScopeFix1012WTests {

    private struct Room {
        let context: NSManagedObjectContext
        let maya = UUID()
        let eli = UUID()
        let lessonID = UUID()
    }

    private func makeRoom() throws -> Room {
        Room(context: try CoreDataTestHelpers.makeContext())
    }

    private func addParticipant(_ studentID: UUID, to work: CDWorkModel, in context: NSManagedObjectContext) {
        let participant = CDWorkParticipantEntity(context: context)
        participant.id = UUID()
        participant.studentID = studentID.uuidString
        participant.work = work
    }

    /// One row per child, each naming both — the shape Quick New Work and
    /// `assign_work` make.
    private func seedLinkedCopies(in room: Room) -> (maya: CDWorkModel, eli: CDWorkModel) {
        let made = Date()
        let rows = [room.maya, room.eli].map { owner -> CDWorkModel in
            let work = CoreDataTestHelpers.seedWorkModel(
                in: room.context, title: "Stamp game", studentID: owner, lessonID: room.lessonID
            )
            work.kind = .practiceLesson
            work.createdAt = made
            addParticipant(room.maya, to: work, in: room.context)
            addParticipant(room.eli, to: work, in: room.context)
            return work
        }
        return (rows[0], rows[1])
    }

    private func linkedStudents(of note: CDNote) -> Set<String> {
        Set(((note.studentLinks?.allObjects as? [CDNoteStudentLink]) ?? []).map(\.studentID))
    }

    @Test("A note on one child's linked copy is hers alone")
    func linkedCopyNoteIsTheOwners() throws {
        let room = try makeRoom()
        let copies = seedLinkedCopies(in: room)
        let checkIn = CDWorkCheckIn.make(for: copies.maya, on: Date(), purpose: "progressCheck", in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(checkIn.setLegacyNoteText("Carried the tens on her own", in: room.context))

        let note = try #require((checkIn.notes?.allObjects as? [CDNote])?.first)
        #expect(note.scope == .student(room.maya), "not on Eli's Notes tab: he has his own copy")
        #expect(linkedStudents(of: note).isEmpty)
    }

    @Test("A check-in made with a note on a linked copy scopes it to the owner")
    func serviceCreatedNoteIsTheOwners() throws {
        let room = try makeRoom()
        let copies = seedLinkedCopies(in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        let checkIn = try WorkCheckInService(context: room.context)
            .createCheckIn(for: copies.eli, date: Date(), note: "Bring the bead frame")

        let note = try #require((checkIn.notes?.allObjects as? [CDNote])?.first)
        #expect(note.scope == .student(room.eli))
    }

    @Test("A shared row's check-in note is about everyone on it")
    func sharedRowNoteNamesEveryone() throws {
        let room = try makeRoom()
        let shared = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Fundamental Needs poster", studentID: room.maya, lessonID: room.lessonID
        )
        shared.kind = .followUpAssignment
        addParticipant(room.maya, to: shared, in: room.context)
        addParticipant(room.eli, to: shared, in: room.context)
        let checkIn = CDWorkCheckIn.make(for: shared, on: Date(), purpose: "progressCheck", in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(checkIn.setLegacyNoteText("Split the drawing between them", in: room.context))

        let note = try #require((checkIn.notes?.allObjects as? [CDNote])?.first)
        #expect(Set(note.scope.studentIDs ?? []) == [room.maya, room.eli])
        #expect(linkedStudents(of: note) == Set([room.maya, room.eli].map(\.uuidString)))
    }

    @Test("A single child's row with no participant rows is still hers")
    func ownerOnlyRowIsTheOwners() throws {
        let room = try makeRoom()
        let work = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Golden beads", studentID: room.maya, lessonID: room.lessonID
        )
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), purpose: "progressCheck", in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(checkIn.setLegacyNoteText("Counted to 9,999", in: room.context))

        let note = try #require((checkIn.notes?.allObjects as? [CDNote])?.first)
        #expect(note.scope == .student(room.maya))
    }
}
