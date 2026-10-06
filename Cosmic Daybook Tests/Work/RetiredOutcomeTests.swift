import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #8. The launch merge folded the retired
// `completionOutcomeRaw` into `statusRaw` but left the outcome on the row.
// A row folded to Mastered, reopened and then closed as plain Done read as
// `complete` + `proficient` again, and the next launch turned it back into
// Mastered, on every device. The outcome is now cleared once it is folded
// (the folded status is the record of it), and so is a leftover one on a row
// an older build already folded.

@Suite("The retired completion outcome is cleared")
@MainActor
struct RetiredOutcomeTests {

    private func row(
        status: WorkStatus, outcome: CompletionOutcome?, in context: NSManagedObjectContext
    ) -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Golden bead addition")
        work.statusRaw = status.rawValue
        work.completionOutcomeRaw = outcome?.rawValue
        return work
    }

    @Test("A row an older build folded to Mastered, reopened and closed as Done, stays Done after the launch pass")
    func reopenedMasteredRowStaysDone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // As an older build left it: folded to Mastered, the outcome kept.
        let work = row(status: .mastered, outcome: .proficient, in: context)
        #expect(CoreDataTestHelpers.save(context))
        DataCleanupService.mergeWorkCompletionOutcomes(using: context)
        #expect(CoreDataTestHelpers.save(context))

        // Reopened, then closed as plain Done, written through `statusRaw`
        // as an undo, a backup restore or an older build's sync writes it.
        work.statusRaw = WorkStatus.active.rawValue
        #expect(CoreDataTestHelpers.save(context))
        work.statusRaw = WorkStatus.done.rawValue
        #expect(CoreDataTestHelpers.save(context))

        DataCleanupService.mergeWorkCompletionOutcomes(using: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(work.statusRaw == WorkStatus.done.rawValue)
    }

    @Test("Folding a legacy row clears its outcome; a second pass changes nothing")
    func foldClearsOutcome() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = row(status: .done, outcome: .proficient, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.mergeWorkCompletionOutcomes(using: context) == 1)
        #expect(CoreDataTestHelpers.save(context))
        #expect(work.statusRaw == WorkStatus.mastered.rawValue)
        #expect(work.completionOutcomeRaw == nil)

        #expect(DataCleanupService.mergeWorkCompletionOutcomes(using: context) == 0)
        #expect(!context.hasChanges)
    }

    @Test("A retired verdict on a closed row leaves it Done, without the outcome")
    func retiredVerdictLeavesDone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = row(status: .done, outcome: .needsReview, in: context)
        #expect(CoreDataTestHelpers.save(context))

        DataCleanupService.mergeWorkCompletionOutcomes(using: context)
        #expect(work.statusRaw == WorkStatus.done.rawValue)
        #expect(work.completionOutcomeRaw == nil)
    }

    @Test("Undoing a logged check puts the old verdict back without the retired outcome")
    func undoRestoresFoldedVerdict() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // A row that arrived from an older device before this one folded it.
        let work = row(status: .done, outcome: .proficient, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let receipt = try WorkLogService.log([.init(work: work, status: .active)], context: context)
        try WorkLogService.undo(receipt.token, context: context)

        #expect(work.statusRaw == WorkStatus.mastered.rawValue)
        #expect(work.completionOutcomeRaw == nil)
        // The launch pass has nothing left to fold.
        #expect(DataCleanupService.mergeWorkCompletionOutcomes(using: context) == 0)
    }
}
