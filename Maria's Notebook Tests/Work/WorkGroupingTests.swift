import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Work Grouping")
@MainActor
struct WorkGroupingTests {

    // MARK: - Fixtures

    /// Builds a fan-out group the way `assign_work` and the Quick New Work
    /// sheet do: one row per child, each row naming itself and every peer.
    @discardableResult
    private func seedLinkedCopies(
        in context: NSManagedObjectContext,
        studentIDs: [UUID],
        lessonID: UUID,
        title: String = "Commutative law follow-up",
        presentationID: UUID? = nil
    ) -> [CDWorkModel] {
        let works = studentIDs.map { studentID -> CDWorkModel in
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: title, studentID: studentID, lessonID: lessonID
            )
            work.id = UUID()
            work.kind = .followUpAssignment
            work.presentationID = presentationID?.uuidString
            addParticipant(studentID, to: work, in: context)
            return work
        }
        for work in works {
            for other in works where other !== work {
                addParticipant(UUID(uuidString: other.studentID)!, to: work, in: context)
            }
        }
        return works
    }

    /// Builds a single row carrying several children, the way project-session
    /// work is built.
    @discardableResult
    private func seedSharedRow(
        in context: NSManagedObjectContext,
        studentIDs: [UUID],
        lessonID: UUID,
        title: String = "Fundamental Needs Poster"
    ) -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: title, studentID: studentIDs[0], lessonID: lessonID
        )
        work.id = UUID()
        work.kind = .followUpAssignment
        for studentID in studentIDs {
            addParticipant(studentID, to: work, in: context)
        }
        return work
    }

    private func addParticipant(
        _ studentID: UUID, to work: CDWorkModel, in context: NSManagedObjectContext
    ) {
        let participant = CDWorkParticipantEntity(context: context)
        participant.id = UUID()
        participant.studentID = studentID.uuidString
        participant.work = work
    }

    // MARK: - Membership

    @Test("studentIDs unions the owner field with the participant rows")
    func studentIDsUnionsOwnerAndParticipants() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let owner = UUID()
        let peer = UUID()
        let work = seedSharedRow(
            in: context, studentIDs: [owner, peer], lessonID: UUID()
        )

        // `createWork` writes the owner into both places; it must count once.
        #expect(WorkGrouping.studentIDs(of: work) == [owner, peer])
        #expect(WorkGrouping.involves(peer, in: work))
        #expect(!WorkGrouping.involves(UUID(), in: work))
    }

    @Test("an empty owner field is a valid state, not a member")
    func emptyOwnerIsNotAMember() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let claimant = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, lessonID: UUID())
        work.studentID = ""
        addParticipant(claimant, to: work, in: context)

        #expect(WorkGrouping.owner(of: work) == nil)
        #expect(WorkGrouping.studentIDs(of: work) == [claimant])
    }

    // MARK: - Shape

    @Test("a fan-out group reads as linked copies from any of its rows")
    func fanOutReadsAsLinkedCopies() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let students = [UUID(), UUID(), UUID()]
        let works = seedLinkedCopies(in: context, studentIDs: students, lessonID: lessonID)
        CoreDataTestHelpers.save(context)

        for work in works {
            let group = WorkGrouping.group(containing: work, in: context)
            #expect(group.shape == .linkedCopies(total: 3))
            #expect(group.members.count == 3)
            #expect(group.siblings.count == 2)
        }
    }

    @Test("a single row carrying several children reads as shared, not as copies")
    func sharedRowReadsAsShared() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let work = seedSharedRow(
            in: context, studentIDs: [UUID(), UUID(), UUID()], lessonID: UUID()
        )
        CoreDataTestHelpers.save(context)

        let group = WorkGrouping.group(containing: work, in: context)
        #expect(group.shape == .shared(childCount: 3))
        #expect(group.siblings.isEmpty)
    }

    @Test("one child on one row reads as single")
    func singleChildReadsAsSingle() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let work = seedSharedRow(in: context, studentIDs: [UUID()], lessonID: UUID())
        CoreDataTestHelpers.save(context)

        #expect(WorkGrouping.group(containing: work, in: context).shape == .single)
    }

    // MARK: - The residue the delete bug leaves

    @Test("a group that lost a row degrades to shared rather than reaching for it")
    func deletedSiblingDegradesToShared() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let naomi = UUID()
        let ora = UUID()
        let works = seedLinkedCopies(in: context, studentIDs: [naomi, ora], lessonID: lessonID)
        CoreDataTestHelpers.save(context)

        // Ora's own row is deleted the way `WorkRepository.deleteWork` does it:
        // the survivor keeps its participant row naming her.
        let orasRow = try #require(works.first { $0.studentID == ora.uuidString })
        let survivor = try #require(works.first { $0.studentID == naomi.uuidString })
        context.delete(orasRow)
        CoreDataTestHelpers.save(context)

        let group = WorkGrouping.group(containing: survivor, in: context)
        #expect(WorkGrouping.studentIDs(of: survivor) == [naomi, ora])
        // Still names Ora, but nothing mutually claims it — so it is read as a
        // single shared row and no other record is implicated.
        #expect(group.shape == .shared(childCount: 2))
        #expect(group.siblings.isEmpty)
    }

    @Test("a partially damaged group still resolves through the rows that remain")
    func partialGroupResolvesTransitively() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let students = [UUID(), UUID(), UUID()]
        let works = seedLinkedCopies(in: context, studentIDs: students, lessonID: lessonID)
        CoreDataTestHelpers.save(context)

        context.delete(works[2])
        CoreDataTestHelpers.save(context)

        let group = WorkGrouping.group(containing: works[0], in: context)
        #expect(group.shape == .linkedCopies(total: 2))
    }

    // MARK: - What the rule refuses to join

    @Test("a one-directional link is not a group")
    func oneDirectionalLinkIsNotAGroup() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let first = UUID()
        let second = UUID()

        // `first`'s row names `second`, but not the other way round.
        let lhs = seedSharedRow(
            in: context, studentIDs: [first, second], lessonID: lessonID, title: "Same title"
        )
        let rhs = seedSharedRow(
            in: context, studentIDs: [second], lessonID: lessonID, title: "Same title"
        )
        CoreDataTestHelpers.save(context)

        #expect(!WorkGrouping.areLinkedCopies(lhs, rhs))
        #expect(WorkGrouping.group(containing: lhs, in: context).siblings.isEmpty)
    }

    @Test("two separate assignments of the same lesson stay separate")
    func differentAssignmentsOfOneLessonStaySeparate() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let students = [UUID(), UUID()]
        let first = seedLinkedCopies(
            in: context, studentIDs: students, lessonID: lessonID, title: "Label the parts"
        )
        let second = seedLinkedCopies(
            in: context, studentIDs: students, lessonID: lessonID, title: "Write a definition"
        )
        CoreDataTestHelpers.save(context)

        let group = WorkGrouping.group(containing: first[0], in: context)
        #expect(group.shape == .linkedCopies(total: 2))
        #expect(!group.members.contains { $0 === second[0] })
    }

    @Test("copies of the same title from different presentations stay separate")
    func differentPresentationsStaySeparate() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let students = [UUID(), UUID()]
        let first = seedLinkedCopies(
            in: context, studentIDs: students, lessonID: lessonID, presentationID: UUID()
        )
        let second = seedLinkedCopies(
            in: context, studentIDs: students, lessonID: lessonID, presentationID: UUID()
        )
        CoreDataTestHelpers.save(context)

        #expect(!WorkGrouping.areLinkedCopies(first[0], second[0]))
        #expect(WorkGrouping.group(containing: first[0], in: context).members.count == 2)
    }

    @Test("titles differing only in spacing or accents still group")
    func titleComparisonIgnoresSpacingAndAccents() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let first = UUID()
        let second = UUID()
        let works = seedLinkedCopies(
            in: context, studentIDs: [first, second], lessonID: lessonID, title: "Étude  des noms"
        )
        works[1].title = "Etude des noms"
        CoreDataTestHelpers.save(context)

        #expect(WorkGrouping.areLinkedCopies(works[0], works[1]))
    }
}
