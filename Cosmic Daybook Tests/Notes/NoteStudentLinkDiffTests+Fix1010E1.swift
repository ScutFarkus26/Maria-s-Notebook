import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Each NoteStudentLink is a synced row. `syncStudentLinks` used to delete
// every link and make new ones on each call, so two devices saving the same
// note each made a set and the note ended up with every child linked twice.
// It is a diff now: a right link stays, a missing child gets one with an id
// every device computes alike, and only links the scope doesn't name go.

@Suite("Note student links diff (Fix1010E1)")
@MainActor
struct NoteStudentLinkDiffTests {

    private func links(of note: CDNote) -> [CDNoteStudentLink] {
        ((note.studentLinks?.allObjects as? [CDNoteStudentLink]) ?? []).filter { !$0.isDeleted }
    }

    private func linkedStudents(of note: CDNote) -> [String] {
        links(of: note).map { $0.studentID.uppercased() }.sorted()
    }

    @Test("Running the diff twice changes nothing the second time")
    func secondRunIsQuiet() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let ora = UUID()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Worked the bead frame together.")
        note.scope = .students([etty, ora])

        #expect(note.syncStudentLinks(in: context))
        #expect(CoreDataTestHelpers.save(context))
        let firstIDs = Set(links(of: note).map(\.objectID))
        #expect(firstIDs.count == 2)

        #expect(!note.syncStudentLinks(in: context))
        #expect(!context.hasChanges)
        #expect(Set(links(of: note).map(\.objectID)) == firstIDs)
    }

    @Test("A new link's id comes from the note and the child")
    func stableIDs() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Read to a friend.")
        note.scope = .students([etty, UUID()])
        note.syncStudentLinks(in: context)

        let noteID = try #require(note.id)
        let ettyLink = try #require(links(of: note).first { $0.studentID == etty.uuidString })
        #expect(ettyLink.id == CDNoteStudentLink.stableID(noteID: noteID, studentID: etty))
        #expect(ettyLink.noteID == noteID.uuidString)
        // Same inputs, same id; different child, different id.
        #expect(CDNoteStudentLink.stableID(noteID: noteID, studentID: etty)
            == CDNoteStudentLink.stableID(noteID: noteID, studentID: etty))
        #expect(CDNoteStudentLink.stableID(noteID: noteID, studentID: etty)
            != CDNoteStudentLink.stableID(noteID: noteID, studentID: UUID()))
    }

    @Test("Re-scoping keeps the links still right and removes only the extras")
    func rescopeIsADiff() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let ora = UUID()
        let tiffy = UUID()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Sorted the cards.")
        note.scope = .students([etty, ora])
        note.syncStudentLinks(in: context)
        #expect(CoreDataTestHelpers.save(context))
        let ettyLink = try #require(links(of: note).first { $0.studentID == etty.uuidString })

        note.scope = .students([etty, tiffy])
        #expect(note.syncStudentLinks(in: context))
        #expect(CoreDataTestHelpers.save(context))

        #expect(linkedStudents(of: note) == [etty, tiffy].map(\.uuidString).sorted())
        #expect(links(of: note).contains { $0.objectID == ettyLink.objectID }, "Etty's link row stays")
    }

    @Test("A one-child or whole-class scope has no links")
    func otherScopesHaveNone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Class meeting.")
        note.scope = .students([UUID(), UUID()])
        note.syncStudentLinks(in: context)
        note.scope = .student(UUID())
        note.syncStudentLinks(in: context)
        #expect(links(of: note).isEmpty)
        note.scope = .all
        #expect(!note.syncStudentLinks(in: context))
    }

    @Test("A child named twice in the scope gets one link")
    func repeatedChildInScope() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Practiced.")
        note.scope = .students([etty, etty, UUID()])
        note.syncStudentLinks(in: context)
        #expect(links(of: note).filter { $0.studentID == etty.uuidString }.count == 1)
    }

    @Test("Old doubles keep one link per child, the same one whichever device looks")
    func oldDoublesFold() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let etty = UUID()
        let ora = UUID()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Made a timeline.")
        note.scope = .students([etty, ora])
        // Two delete-and-recreate saves on two devices: random ids, twice over.
        for student in [etty, etty, ora, ora] {
            let link = CDNoteStudentLink(context: context)
            link.noteID = note.id?.uuidString ?? ""
            link.studentID = student.uuidString
            link.note = note
        }
        #expect(CoreDataTestHelpers.save(context))

        // A second device reading the same rows picks the same keepers.
        let other = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        other.persistentStoreCoordinator = context.persistentStoreCoordinator
        let noteID = try #require(note.id)
        let otherNote = try #require(other.object(CDNote.self, id: noteID))
        for student in [etty, ora] {
            let stable = CDNoteStudentLink.stableID(noteID: noteID, studentID: student)
            let here = links(of: note).filter { $0.studentID == student.uuidString }
            let there = links(of: otherNote).filter { $0.studentID == student.uuidString }
            #expect(CDNoteStudentLink.keeper(of: here, stableID: stable)?.id
                == CDNoteStudentLink.keeper(of: there, stableID: stable)?.id)
        }

        #expect(note.syncStudentLinks(in: context))
        #expect(CoreDataTestHelpers.save(context))
        #expect(linkedStudents(of: note) == [etty, ora].map(\.uuidString).sorted())
    }

    @Test("Two devices adding the same links at once end with one link per child")
    func twoDevicesConverge() throws {
        // Two devices' stores, each holding the same note before either adds links.
        let deviceA = try CoreDataTestHelpers.makeContext()
        let deviceB = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let ora = UUID()
        let note = CoreDataTestHelpers.seedNote(in: deviceA, body: "Built the trinomial cube.")
        note.scope = .students([etty, ora])
        let noteID = try #require(note.id)
        let copy = CoreDataTestHelpers.seedNote(in: deviceB, body: "Built the trinomial cube.")
        copy.id = noteID
        copy.scope = .students([etty, ora])
        #expect(CoreDataTestHelpers.save(deviceA))
        #expect(CoreDataTestHelpers.save(deviceB))

        // Each adds the missing links (a repair run on both, say).
        #expect(note.syncStudentLinks(in: deviceA))
        #expect(copy.syncStudentLinks(in: deviceB))
        #expect(CoreDataTestHelpers.save(deviceA))
        #expect(CoreDataTestHelpers.save(deviceB))
        // Both computed the same ids.
        #expect(Set(links(of: note).compactMap(\.id)) == Set(links(of: copy).compactMap(\.id)))

        // B's links reach A through iCloud: rows of their own, carrying B's ids.
        for link in links(of: copy) {
            let arrived = CDNoteStudentLink(context: deviceA)
            arrived.id = link.id
            arrived.noteID = link.noteID
            arrived.studentID = link.studentID
            arrived.note = note
        }
        #expect(CoreDataTestHelpers.save(deviceA))
        #expect(links(of: note).count == 4)

        // The deduplication folds each same-id pair into one, and nothing is left to change.
        #expect(DataCleanupService.deduplicate(CDNoteStudentLink.self, using: deviceA) == 2)
        #expect(linkedStudents(of: note) == [etty, ora].map(\.uuidString).sorted())
        #expect(!note.syncStudentLinks(in: deviceA), "nothing left to change")
    }

    @Test("A group check-in's note gets a link for each child")
    func groupCheckInNoteLinks() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let ora = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead chains", studentID: etty)
        for student in [etty, ora] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.studentID = student.uuidString
            participant.work = work
        }
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.work = work
        checkIn.workID = work.id?.uuidString ?? ""

        #expect(checkIn.setLegacyNoteText("Counted the 7 chain together.", in: context))
        #expect(CoreDataTestHelpers.save(context))
        let note = try #require((checkIn.notes?.allObjects as? [CDNote])?.first)
        #expect(linkedStudents(of: note) == [etty, ora].map(\.uuidString).sorted())
    }

    @Test("A project session's note is about the project's members")
    func projectSessionNoteScope() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = UUID()
        let ora = UUID()
        let project = CDProject(context: context)
        project.title = "Book club"
        project.memberStudentUUIDs = [etty, ora]
        let session = CDProjectSession(context: context)
        session.project = project

        session.setLegacyNoteText("Discussed chapter 3.", in: context)
        let note = try #require((session.noteItems?.allObjects as? [CDNote])?.first)
        #expect(Set(note.scope.studentIDs ?? []) == Set([etty, ora]))
        #expect(!note.scopeIsAll)
        #expect(linkedStudents(of: note) == [etty, ora].map(\.uuidString).sorted())
    }
}
