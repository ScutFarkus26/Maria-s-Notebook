import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Presentation Follow-Up Editor")
@MainActor
final class PresentationFollowUpEditorModelTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let rows: [CDLessonPresentation]
        let beganAt: Date
    }

    private struct FollowUpBundle: Equatable {
        let actionRaw: String?
        let reviewAt: Date?
        let resolvedAt: Date?
        let resolutionRaw: String?
        let updatedAt: Date?
        let evidenceRaw: String?
        let note: String?
        let supportRaw: String?

        init(row: CDLessonPresentation) {
            actionRaw = row.followUpActionRaw
            reviewAt = row.followUpReviewAt
            resolvedAt = row.followUpResolvedAt
            resolutionRaw = row.followUpResolutionRaw
            updatedAt = row.followUpUpdatedAt
            evidenceRaw = row.followUpEvidenceRaw
            note = row.followUpNote
            supportRaw = row.followUpSupportRaw
        }
    }

    private func makeFixture(rowCount: Int = 2) throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let presentationID = UUID().uuidString
        let beganAt = Date(timeIntervalSinceReferenceDate: 802_000_000)
        let rows = (0..<rowCount).map { _ in
            let row = CDLessonPresentation(context: context)
            row.studentID = UUID().uuidString
            row.lessonID = UUID().uuidString
            row.presentationID = presentationID
            PresentationFollowUpService.beginFollowing(row, at: beganAt)
            return row
        }
        try context.save()
        return Fixture(context: context, rows: rows, beganAt: beganAt)
    }

    @Test("Every action remains selectable, including repeated detail changes")
    func repeatedActionsRemainSelectable() throws {
        let fixture = try makeFixture()
        let model = PresentationFollowUpEditorModel()
        let firstReview = fixture.beganAt.addingTimeInterval(86_400)
        let secondReview = firstReview.addingTimeInterval(86_400)
        var persistCount = 0

        func choose(
            _ action: PresentationFollowUpAction,
            reviewAt: Date? = nil,
            support: PresentationFollowUpSupport? = nil
        ) {
            let saved = model.selectAction(
                action,
                rows: fixture.rows,
                reviewAt: reviewAt,
                support: support,
                persist: {
                    persistCount += 1
                    #expect(model.selectedAction == action)
                    return true
                }
            )
            #expect(saved)
            #expect(model.selectedAction == action)
            #expect(fixture.rows.allSatisfy { $0.followUpAction == action })
        }

        choose(.checkWork, reviewAt: firstReview)
        #expect(model.reviewAt == AppCalendar.startOfDay(firstReview))
        choose(.checkWork, reviewAt: secondReview)
        #expect(model.reviewAt == AppCalendar.startOfDay(secondReview))

        choose(.planSupport, support: .confer)
        #expect(model.selectedSupport == .confer)
        choose(.planSupport, support: .represent)
        #expect(model.selectedSupport == .represent)

        choose(.planNextPresentation)
        choose(.watchWork)

        #expect(persistCount == 6)
        #expect(model.reviewAt == nil)
        #expect(model.selectedSupport == nil)
    }

    @Test("Every follow-up path can switch to every other path")
    func everyActionTransitionRemainsSelectable() throws {
        let fixture = try makeFixture()
        let model = PresentationFollowUpEditorModel()

        for startingAction in PresentationFollowUpAction.allCases {
            #expect(model.selectAction(
                startingAction,
                rows: fixture.rows,
                persist: { true }
            ))

            for destinationAction in PresentationFollowUpAction.allCases {
                #expect(model.selectAction(
                    destinationAction,
                    rows: fixture.rows,
                    persist: { true }
                ))
                #expect(model.selectedAction == destinationAction)
                #expect(fixture.rows.allSatisfy {
                    $0.followUpAction == destinationAction
                })
            }
        }
    }

    @Test("Scope can apply an action to all children or one child")
    func allAndChildScopes() throws {
        let fixture = try makeFixture()
        let firstRow = try #require(fixture.rows.first)
        let secondRow = try #require(fixture.rows.last)
        let model = PresentationFollowUpEditorModel()

        model.setScope(.child(firstRow.objectID), rows: fixture.rows)
        #expect(model.rowsInScope(from: fixture.rows).map(\.objectID) == [firstRow.objectID])

        #expect(model.selectAction(
            .planSupport,
            rows: fixture.rows,
            support: .confer,
            persist: { true }
        ))
        #expect(firstRow.followUpAction == .planSupport)
        #expect(firstRow.followUpSupport == .confer)
        #expect(secondRow.followUpAction == .watchWork)

        model.setScope(.allChildren, rows: fixture.rows)
        #expect(model.hasMixedActions)

        #expect(model.selectAction(
            .checkWork,
            rows: fixture.rows,
            reviewAt: fixture.beganAt,
            persist: { true }
        ))
        #expect(fixture.rows.allSatisfy { $0.followUpAction == .checkWork })
        #expect(fixture.rows.allSatisfy { $0.followUpReviewAt == AppCalendar.startOfDay(fixture.beganAt) })
    }

    @Test("Mixed child actions hydrate as multiple values")
    func mixedState() throws {
        let fixture = try makeFixture()
        let firstRow = try #require(fixture.rows.first)
        let secondRow = try #require(fixture.rows.last)
        let reviewAt = fixture.beganAt.addingTimeInterval(86_400)
        PresentationFollowUpService.setAction(.checkWork, for: [firstRow], reviewAt: reviewAt)
        PresentationFollowUpService.setAction(.planSupport, for: [secondRow], support: .confer)

        let model = PresentationFollowUpEditorModel()
        model.synchronize(from: fixture.rows)

        #expect(model.selectedAction == nil)
        #expect(model.hasMixedActions)
        #expect(model.reviewAt == nil)
        #expect(model.selectedSupport == nil)

        model.setScope(.child(secondRow.objectID), rows: fixture.rows)
        #expect(model.selectedAction == .planSupport)
        #expect(!model.hasMixedActions)
        #expect(model.selectedSupport == .confer)
    }

    @Test("A reopened editor hydrates the existing follow-up")
    func reopenedEditorHydratesExistingState() throws {
        let fixture = try makeFixture()
        let reviewAt = fixture.beganAt.addingTimeInterval(150_000)
        PresentationFollowUpService.setAction(.checkWork, for: fixture.rows, reviewAt: reviewAt)
        PresentationFollowUpService.resolve(
            .continueIndependentWork,
            row: fixture.rows[0],
            at: fixture.beganAt.addingTimeInterval(3_600)
        )
        PresentationFollowUpService.reopen(
            fixture.rows[0],
            at: fixture.beganAt.addingTimeInterval(7_200)
        )
        try fixture.context.save()

        let reopenedModel = PresentationFollowUpEditorModel()
        reopenedModel.synchronize(from: fixture.rows)

        #expect(reopenedModel.selectedAction == .checkWork)
        #expect(!reopenedModel.hasMixedActions)
        #expect(reopenedModel.reviewAt == AppCalendar.startOfDay(reviewAt))
        #expect(reopenedModel.selectedSupport == nil)
    }

    @Test("Changing paths clears details belonging to the previous path")
    func staleDetailsAreCleared() throws {
        let fixture = try makeFixture(rowCount: 1)
        let row = try #require(fixture.rows.first)
        let model = PresentationFollowUpEditorModel()

        #expect(model.selectAction(
            .checkWork,
            rows: fixture.rows,
            reviewAt: fixture.beganAt,
            persist: { true }
        ))
        #expect(model.reviewAt != nil)
        #expect(row.followUpReviewAt != nil)

        #expect(model.selectAction(
            .planSupport,
            rows: fixture.rows,
            support: .confer,
            persist: { true }
        ))
        #expect(model.reviewAt == nil)
        #expect(row.followUpReviewAt == nil)
        #expect(model.selectedSupport == .confer)
        #expect(row.followUpSupport == .confer)

        #expect(model.selectAction(.watchWork, rows: fixture.rows, persist: { true }))
        #expect(model.selectedSupport == nil)
        #expect(row.followUpSupport == nil)
    }

    @Test("A failed save restores only the affected follow-up bundle")
    func failedSaveRestoresAffectedBundle() throws {
        let fixture = try makeFixture()
        let firstRow = try #require(fixture.rows.first)
        let secondRow = try #require(fixture.rows.last)
        let originalReview = fixture.beganAt.addingTimeInterval(86_400)

        PresentationFollowUpService.setAction(.checkWork, for: [firstRow], reviewAt: originalReview)
        firstRow.followUpEvidenceRaw = PresentationFollowUpEvidence.concentrated.rawValue
        firstRow.followUpNote = "Repeated the sequence."
        PresentationFollowUpService.setAction(.planSupport, for: [secondRow], support: .confer)
        try fixture.context.save()

        let firstBundle = FollowUpBundle(row: firstRow)
        let secondBundle = FollowUpBundle(row: secondRow)
        let model = PresentationFollowUpEditorModel()
        model.setScope(.child(firstRow.objectID), rows: fixture.rows)
        var observedSynchronousState = false

        let saved = model.selectAction(
            .planSupport,
            rows: fixture.rows,
            support: .represent,
            persist: {
                observedSynchronousState = model.selectedAction == .planSupport
                    && model.selectedSupport == .represent
                    && firstRow.followUpAction == .planSupport
                return false
            }
        )

        #expect(!saved)
        #expect(observedSynchronousState)
        #expect(FollowUpBundle(row: firstRow) == firstBundle)
        #expect(FollowUpBundle(row: secondRow) == secondBundle)
        #expect(model.selectedAction == .checkWork)
        #expect(model.reviewAt == AppCalendar.startOfDay(originalReview))
        #expect(model.selectedSupport == nil)
    }

    @Test("Resolving a child preserves that child's work scope without leaving an active guide action")
    func resolvingSelectedChildPreservesWorkScope() throws {
        let fixture = try makeFixture()
        let selectedRow = try #require(fixture.rows.first)
        let remainingRow = try #require(fixture.rows.last)
        let model = PresentationFollowUpEditorModel()

        model.setScope(.child(selectedRow.objectID), rows: fixture.rows)
        PresentationFollowUpService.resolve(
            .continueIndependentWork,
            row: selectedRow,
            at: fixture.beganAt.addingTimeInterval(3_600)
        )
        PresentationFollowUpService.setAction(
            .planSupport,
            for: [remainingRow],
            support: .confer
        )

        model.synchronize(from: fixture.rows)

        #expect(model.scope == .child(selectedRow.objectID))
        #expect(model.rowsInScope(from: fixture.rows).isEmpty)
        #expect(model.selectedAction == nil)
        #expect(model.selectedSupport == nil)
    }
}
