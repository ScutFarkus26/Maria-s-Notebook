import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The fold of the retired completion outcome into the single `WorkStatus`.
/// One table, read by the launch repair and the backup importer alike.
@Suite("Work status migration")
@MainActor
struct WorkStatusMigrationTests {

    // MARK: - The table

    @Test(
        "A closed row with an outcome takes the merged word",
        arguments: [
            ("mastered", "mastered"),
            ("needsMorePractice", "keepPracticing"),
            ("incomplete", "incomplete"),
            // Verdicts the merged vocabulary does not keep stay a plain Done.
            ("needsReview", "complete"),
            ("notApplicable", "complete"),
            ("something-no-build-ever-wrote", "complete")
        ]
    )
    func closedRowsMerge(outcomeRaw: String, expected: String) {
        #expect(WorkStatusMigration.merged(statusRaw: "complete", outcomeRaw: outcomeRaw) == expected)
    }

    @Test("A closed row with no outcome stays Done")
    func noOutcomeStaysDone() {
        #expect(WorkStatusMigration.merged(statusRaw: "complete", outcomeRaw: nil) == "complete")
        #expect(WorkStatusMigration.mergedStatus(statusRaw: "complete", outcomeRaw: nil) == .done)
    }

    @Test("Open rows keep their status whatever the outcome column says", arguments: ["active", "review"])
    func openRowsUntouched(statusRaw: String) {
        #expect(WorkStatusMigration.merged(statusRaw: statusRaw, outcomeRaw: "mastered") == statusRaw)
        #expect(WorkStatusMigration.merged(statusRaw: statusRaw, outcomeRaw: nil) == statusRaw)
    }

    @Test("The fold is idempotent", arguments: WorkStatus.allCases)
    func idempotent(status: WorkStatus) {
        let once = WorkStatusMigration.merged(statusRaw: status.rawValue, outcomeRaw: "needsMorePractice")
        let twice = WorkStatusMigration.merged(statusRaw: once, outcomeRaw: "needsMorePractice")
        #expect(once == twice)
    }

    @Test("An unknown raw value reads as Working, never as closed")
    func unknownRawIsOpen() {
        #expect(WorkStatusMigration.mergedStatus(statusRaw: "archived", outcomeRaw: nil) == .active)
    }

    // MARK: - The launch pass

    @Test("The launch pass rewrites only the legacy pair and keeps the outcome column")
    func launchPassRewritesLegacyRows() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let proficientRow = CoreDataTestHelpers.seedWorkModel(in: context, title: "Mastered")
        proficientRow.statusRaw = "complete"
        proficientRow.completionOutcomeRaw = "mastered"

        let practicing = CoreDataTestHelpers.seedWorkModel(in: context, title: "Keep practicing")
        practicing.statusRaw = "complete"
        practicing.completionOutcomeRaw = "needsMorePractice"

        let plainDone = CoreDataTestHelpers.seedWorkModel(in: context, title: "Done")
        plainDone.statusRaw = "complete"

        let open = CoreDataTestHelpers.seedWorkModel(in: context, title: "Open")
        open.statusRaw = "review"
        open.completionOutcomeRaw = "mastered"
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.mergeWorkCompletionOutcomes(using: context) == 2)
        #expect(proficientRow.status == .mastered)
        #expect(practicing.status == .keepPracticing)
        #expect(plainDone.status == .done)
        #expect(open.status == .review)
        // The old column is the record of what was there; nothing clears it.
        #expect(proficientRow.completionOutcomeRaw == "mastered")

        // A second pass on a merged store finds nothing to do.
        #expect(DataCleanupService.mergeWorkCompletionOutcomes(using: context) == 0)
    }

    // MARK: - The backup importer

    @Test("An old backup's complete + outcome restores as the merged status")
    func importerFoldsLegacyBackups() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let dto = WorkModelDTO(
            id: UUID(), title: "Golden beads", workTypeRaw: "Research", studentLessonID: nil,
            createdAt: Date(), completedAt: Date(), kindRaw: "practiceLesson", statusRaw: "complete",
            assignedAt: Date(), lastTouchedAt: nil, dueAt: nil, completionOutcomeRaw: "mastered",
            studentID: UUID().uuidString, lessonID: UUID().uuidString, presentationID: nil,
            trackID: nil, trackStepID: nil, scheduledNote: nil, scheduledReasonRaw: nil,
            sourceContextTypeRaw: nil, sourceContextID: nil, sampleWorkID: nil,
            checkInStyleRaw: nil, restingUntil: nil
        )

        BackupEntityImporter.importWorkModels([dto], into: context, existing: { _ in nil })

        let request = CDFetchRequest(CDWorkModel.self)
        let restored = try #require(context.safeFetch(request).first)
        #expect(restored.status == .mastered)
        #expect(restored.completionOutcomeRaw == "mastered")
    }
}
