import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The meeting card's choices (2026-10-30): Ready for Next is a switch beside
// the card's choice, not one of them, and the first choice is named for the
// kind of work. The rest of Ready for Next's tests are in +LessonDecisions,
// +LessonPlans and +Fix1010B.
extension MeetingDraftStoreTests {

    @Test("Ready for Next on its own leaves the work as it is and the card still undecided")
    @MainActor
    func readyForNextAloneIsNotADecision() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stamp Game", studentID: child)
        #expect(CoreDataTestHelpers.save(context))

        let workID = try #require(work.id)
        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        draft.setReadyForNext(true, for: work)
        #expect(work.status == .active)
        #expect(draft.readyWorkIDs == [workID])
        #expect(draft.reviewedWorkIDs.isEmpty)
        #expect(draft.closeTokens.isEmpty)
        #expect(MeetingPersistenceService.loadCurrent(studentID: child).readyWorkIDs == [workID.uuidString])

        draft.setReadyForNext(false, for: work)
        #expect(draft.readyWorkIDs.isEmpty)
        #expect(MeetingPersistenceService.loadCurrent(studentID: child).isEmpty)
    }

    @Test("The first choice says Keep Practicing for practice work and Keep Working for an assignment")
    @MainActor
    func keepGoingLabelFollowsTheKind() throws {
        #expect(WorkDecisionCard.keepGoingLabel(for: .practiceLesson) == "Keep Practicing")
        #expect(WorkDecisionCard.keepGoingLabel(for: .followUpAssignment) == "Keep Working")
        #expect(WorkDecisionCard.keepGoingLabel(for: .research) == "Keep Working")
        #expect(WorkDecisionCard.keepGoingLabel(for: .report) == "Keep Working")
        // Untagged work reads as Practice everywhere else, so it does here.
        let context = try CoreDataTestHelpers.makeContext()
        let untagged = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame", studentID: UUID())
        untagged.kind = nil
        #expect(WorkDecisionCard.keepGoingLabel(for: untagged.displayKind) == "Keep Practicing")
    }
}
