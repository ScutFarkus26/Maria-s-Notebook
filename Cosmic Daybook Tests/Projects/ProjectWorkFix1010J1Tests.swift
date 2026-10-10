import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, Part 2 #84 and #89: taking a child off project work
/// could leave her as its owner, and a new check-in made work for children who
/// had left the class.
@Suite("Project work owner and members (fix 10-10 J1)")
@MainActor
struct ProjectWorkFix1010J1Tests {

    private func addParticipant(_ id: UUID, to work: CDWorkModel, in context: NSManagedObjectContext) {
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = id.uuidString
        participant.work = work
    }

    @Test("Taking the owner off project work hands it to another participant, never back to her")
    func heirExcludesRemovedChild() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let owner = UUID()
        let others = [UUID(), UUID(), UUID()]
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Mural", studentID: owner)
        for id in [owner] + others {
            addParticipant(id, to: work, in: context)
        }
        #expect(CoreDataTestHelpers.save(context))

        SessionWorkAssignmentService(context: context).removeSelection(work: work, studentID: owner)

        let expected = try #require(others.min { $0.uuidString < $1.uuidString })
        #expect(work.studentID == expected.uuidString)
        #expect(CoreDataTestHelpers.save(context))
        let remaining = (work.participants as? Set<CDWorkParticipantEntity>) ?? []
        #expect(!remaining.contains { $0.studentID == owner.uuidString })
    }

    @Test("Taking the last participant off leaves the work with no owner")
    func lastParticipantClearsOwner() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let owner = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Mural", studentID: owner)
        addParticipant(owner, to: work, in: context)
        #expect(CoreDataTestHelpers.save(context))

        SessionWorkAssignmentService(context: context).removeSelection(work: work, studentID: owner)

        #expect(work.studentID.isEmpty)
    }

    @Test("A project check-in's members are the children still enrolled")
    func checkInMembersAreEnrolled() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let left = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Sarah", lastName: "Klein", enrollmentStatus: .withdrawn
        )
        let project = CDProject(context: context)
        project.title = "Ancient Egypt"
        project.memberStudentIDsArray = [try #require(etty.id).uuidString, try #require(left.id).uuidString]
        #expect(CoreDataTestHelpers.save(context))

        let members = SessionWorkAssignmentService.enrolledMemberIDs(of: project, in: context)

        #expect(members == [try #require(etty.id).uuidString])
    }
}
