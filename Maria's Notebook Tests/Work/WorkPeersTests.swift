import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// "Who else is doing this?" — the answer a work card and a lesson card give.
///
/// The rule worth pinning is how much wider this is than `WorkGrouping`: that
/// recovers the rows created together, while this counts anyone doing the same
/// work however she came by it.
@Suite("Work peers")
@MainActor
struct WorkPeersTests {

    // MARK: - Fixtures

    private struct Classroom {
        let context: NSManagedObjectContext

        @discardableResult
        func child(_ first: String, _ last: String) -> UUID {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: first, lastName: last)
            let id = UUID()
            student.id = id
            return id
        }

        @discardableResult
        func work(
            _ title: String,
            for owner: UUID,
            on lessonID: UUID,
            kind: WorkKind = .followUpAssignment,
            status: WorkStatus = .active,
            alsoNaming others: [UUID] = []
        ) -> CDWorkModel {
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: title, studentID: owner, lessonID: lessonID
            )
            work.id = UUID()
            work.kind = kind
            work.status = status
            work.createdAt = Date()
            for studentID in [owner] + others {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = studentID.uuidString
                participant.work = work
            }
            return work
        }

        /// One row per child, each naming the whole group — what `assign_work`
        /// and the Quick New Work sheet write.
        func fanOut(_ title: String, to children: [UUID], on lessonID: UUID) -> [CDWorkModel] {
            children.map { child in
                work(title, for: child, on: lessonID, alsoNaming: children.filter { $0 != child })
            }
        }
    }

    private func makeClassroom() throws -> Classroom {
        Classroom(context: try CoreDataTestHelpers.makeInMemoryStack().viewContext)
    }

    // MARK: - From a work card

    @Test("A fan-out names the other children, and not the one asked from")
    func fanOutNamesTheOthers() throws {
        let room = try makeClassroom()
        let naomi = room.child("Naomi", "Feldman")
        let simma = room.child("Simma", "Zeitlin")
        let etty = room.child("Etty", "Deutsch")
        let lessonID = UUID()
        let copies = room.fanOut("Compound Skyscraper Drawers", to: [naomi, simma, etty], on: lessonID)
        CoreDataTestHelpers.save(room.context)

        let list = WorkPeers.others(doing: copies[0], in: room.context)

        #expect(list.peers.map(\.name) == ["Etty D", "Simma Z"])
        #expect(list.finishedCount == 0)
        // Each name points at that child's own copy, not at the card's row.
        let simmasCopy = try #require(copies.first { $0.studentID == simma.uuidString })
        #expect(list.peers.first { $0.name == "Simma Z" }?.workID == simmasCopy.id)
        #expect(!list.peers.contains { $0.name == "Naomi F" })
    }

    @Test("The same work given separately counts too")
    func separatelyAssignedSameWorkCounts() throws {
        let room = try makeClassroom()
        let naomi = room.child("Naomi", "Feldman")
        let ora = room.child("Ora", "Perl")
        let lessonID = UUID()
        let naomis = room.work("Label the multiplier", for: naomi, on: lessonID)
        // A week later, on its own. `WorkGrouping` would not call this a
        // sibling — nothing links the two rows — but Ora is doing the same work.
        room.work("Label the multiplier", for: ora, on: lessonID)
        CoreDataTestHelpers.save(room.context)

        #expect(WorkPeers.others(doing: naomis, in: room.context).peers.map(\.name) == ["Ora P"])
    }

    @Test("Other work on the same lesson is not the same work")
    func otherWorkOnTheLessonIsNotCounted() throws {
        let room = try makeClassroom()
        let naomi = room.child("Naomi", "Feldman")
        let ora = room.child("Ora", "Perl")
        let lessonID = UUID()
        let naomis = room.work("Label the multiplier", for: naomi, on: lessonID)
        room.work("Write a report on it", for: ora, on: lessonID)
        // Nor is the same title on a different lesson.
        room.work("Label the multiplier", for: ora, on: UUID())
        CoreDataTestHelpers.save(room.context)

        #expect(WorkPeers.others(doing: naomis, in: room.context).isEmpty)
    }

    @Test("Titles differing only in spacing or accents are the same work")
    func titleComparisonIgnoresSpacingAndAccents() throws {
        let room = try makeClassroom()
        let naomi = room.child("Naomi", "Feldman")
        let ora = room.child("Ora", "Perl")
        let lessonID = UUID()
        let naomis = room.work("Étude  des noms", for: naomi, on: lessonID)
        room.work("Etude des noms", for: ora, on: lessonID)
        CoreDataTestHelpers.save(room.context)

        #expect(WorkPeers.others(doing: naomis, in: room.context).peers.map(\.name) == ["Ora P"])
    }

    @Test("Children riding on a shared row are doing that very work")
    func sharedRowPassengersAreCounted() throws {
        let room = try makeClassroom()
        let leshem = room.child("Leshem", "Adler")
        let avigail = room.child("Avigail", "Gold")
        let row = room.work(
            "Fundamental Needs Poster", for: leshem, on: UUID(), alsoNaming: [avigail]
        )
        CoreDataTestHelpers.save(room.context)

        let list = WorkPeers.others(doing: row, in: room.context)

        // Avigail owns no row of her own, so she is pointed at the one she
        // rides on — the same record the guide is looking at.
        #expect(list.peers.map(\.name) == ["Avigail G"])
        #expect(list.peers[0].workID == row.id)
    }

    @Test("A child who has finished it is counted, not listed")
    func finishedCopiesAreCountedSeparately() throws {
        let room = try makeClassroom()
        let naomi = room.child("Naomi", "Feldman")
        let simma = room.child("Simma", "Zeitlin")
        let ora = room.child("Ora", "Perl")
        let lessonID = UUID()
        let naomis = room.work("Compound Skyscraper Drawers", for: naomi, on: lessonID)
        room.work("Compound Skyscraper Drawers", for: simma, on: lessonID)
        room.work("Compound Skyscraper Drawers", for: ora, on: lessonID, status: .complete)
        CoreDataTestHelpers.save(room.context)

        let list = WorkPeers.others(doing: naomis, in: room.context)

        // Finished work has left the workspace, so there is nowhere to send
        // the guide — but she should still know Ora got through it.
        #expect(list.peers.map(\.name) == ["Simma Z"])
        #expect(list.finishedCount == 1)
    }

    @Test("Nobody else is an empty answer, not a missing one")
    func noPeersIsEmpty() throws {
        let room = try makeClassroom()
        let naomi = room.child("Naomi", "Feldman")
        let onlyCopy = room.work("Bank Game", for: naomi, on: UUID())
        CoreDataTestHelpers.save(room.context)

        #expect(WorkPeers.others(doing: onlyCopy, in: room.context) == .none)
    }

    @Test("A child the roster no longer knows is left out rather than unnamed")
    func unresolvableChildrenAreDropped() throws {
        let room = try makeClassroom()
        let naomi = room.child("Naomi", "Feldman")
        let lessonID = UUID()
        let naomis = room.work("Compound Skyscraper Drawers", for: naomi, on: lessonID)
        // A row pointing at a student record that is not there.
        room.work("Compound Skyscraper Drawers", for: UUID(), on: lessonID)
        CoreDataTestHelpers.save(room.context)

        #expect(WorkPeers.others(doing: naomis, in: room.context).isEmpty)
    }

    // MARK: - From a lesson card

    @Test("A lesson lists everyone working on it, whatever the work")
    func lessonListsAllOpenWorkOnIt() throws {
        let room = try makeClassroom()
        let naomi = room.child("Naomi", "Feldman")
        let ora = room.child("Ora", "Perl")
        let baila = room.child("Baila", "Gross")
        let lessonID = UUID()
        room.work("Label the multiplier", for: naomi, on: lessonID, kind: .practiceLesson)
        room.work("Write a report on it", for: ora, on: lessonID, kind: .report)
        room.work("Label the multiplier", for: baila, on: UUID())
        CoreDataTestHelpers.save(room.context)

        let list = WorkPeers.children(workingOn: lessonID, in: room.context)

        #expect(list.peers.map(\.name) == ["Naomi F", "Ora P"])
        // Here the work is what tells the rows apart, so it is what each says.
        #expect(list.peers.map(\.detail) == ["Label the multiplier · 0d", "Write a report on it · 0d"])
    }

    @Test("From a work card the detail names the kind, not the shared title")
    func workCardDetailNamesTheKind() throws {
        let room = try makeClassroom()
        let naomi = room.child("Naomi", "Feldman")
        let ora = room.child("Ora", "Perl")
        let lessonID = UUID()
        let naomis = room.work("Label the multiplier", for: naomi, on: lessonID)
        room.work("Label the multiplier", for: ora, on: lessonID, kind: .practiceLesson)
        CoreDataTestHelpers.save(room.context)

        // Every row here carries the same title, so repeating it says nothing;
        // what differs is that Ora has it as practice.
        #expect(WorkPeers.others(doing: naomis, in: room.context).peers.map(\.detail) == ["Practice · 0d"])
    }
}
