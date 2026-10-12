import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11 follow-up to #65: Uniform project work now carries
// `.projectSession`, the type that used to mark only choice-mode offered work.
// Only offered work (a choice session's row) may be left with nobody on it;
// a Uniform row's last child is refused, as any one-child row is.
@Suite("Work Deletion: project rows (2026-10-11)")
@MainActor
struct WorkDeletionServiceFix1011MainTests {

    private func seedProjectRow(
        mode: SessionAssignmentMode?, in context: NSManagedObjectContext
    ) -> (work: CDWorkModel, child: UUID) {
        let child = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Water cycle poster", studentID: child, lessonID: UUID()
        )
        work.kind = .followUpAssignment
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = child.uuidString
        participant.work = work
        work.sourceContextType = .projectSession
        if let mode {
            let session = CDProjectSession(context: context)
            session.assignmentMode = mode
            work.sourceContextID = session.id?.uuidString ?? ""
        } else {
            work.sourceContextID = UUID().uuidString
        }
        CoreDataTestHelpers.save(context)
        return (work, child)
    }

    @Test("a choice session's offered row may be left with nobody on it")
    func offeredRowMayBeEmptied() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (work, child) = seedProjectRow(mode: .choice, in: context)

        try WorkDeletionService(context: context).remove(studentID: child, from: work)
        #expect(!work.isDeleted)
        #expect(work.studentID.isEmpty)
    }

    @Test("a Uniform row's last child is refused rather than leaving an ownerless row")
    func uniformRowIsNotEmptied() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (work, child) = seedProjectRow(mode: .uniform, in: context)

        #expect(throws: WorkDeletionService.ServiceError.wouldEmptyRow) {
            try WorkDeletionService(context: context).removalPlan(for: child, from: work)
        }
        #expect(work.studentID == child.uuidString)
    }

    @Test("a project row whose session isn't on this device is refused")
    func rowWithoutItsSessionIsNotEmptied() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (work, child) = seedProjectRow(mode: nil, in: context)

        #expect(throws: WorkDeletionService.ServiceError.wouldEmptyRow) {
            try WorkDeletionService(context: context).removalPlan(for: child, from: work)
        }
    }
}
