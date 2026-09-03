import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Presentation Follow-Up Lifecycle")
@MainActor
final class PresentationFollowUpLifecycleTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let coordinator: SaveCoordinator
        let lesson: CDLesson
        let students: [CDStudent]
        let assignment: CDLessonAssignment
        let presentedDay: Date
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true

        let lesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "Golden Beads",
            area: "",
            sequence: ""
        )
        let students = [
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada"),
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        ]
        let presentedDay = AppCalendar.startOfDay(
            Date(timeIntervalSinceReferenceDate: 801_234_567)
        )
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson,
            students: students,
            scheduledFor: presentedDay.addingTimeInterval(-86_400),
            context: context
        )
        try context.save()

        return Fixture(
            context: context,
            coordinator: coordinator,
            lesson: lesson,
            students: students,
            assignment: assignment,
            presentedDay: presentedDay
        )
    }

    private func record(_ fixture: Fixture) throws -> [CDLessonPresentation] {
        _ = try ImmediatePresentationRecordingService.record(
            assignment: fixture.assignment,
            presentedOn: fixture.presentedDay,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )
        let assignmentID = try #require(fixture.assignment.id)
        return PresentationFollowUpService.rows(
            for: assignmentID,
            in: fixture.context
        )
    }

    @Test("Dismissing reflection continues to follow-up and only Close dismisses the lesson")
    func reflectionDismissalDoesNotCloseDetail() {
        var state = PostPresentationFlowState()
        state.beginReflection()

        state.reflectionDidDismiss(
            presentationIsRecorded: true,
            hasOpenFollowUp: true
        )

        #expect(state.phase == .followUp)
        #expect(!state.shouldDismissDetail)

        state.close()

        #expect(state.phase == .closed)
        #expect(state.shouldDismissDetail)
    }

    @Test("Dismissing reflection without an open follow-up returns to the lesson instead of closing")
    func reflectionDismissalWithoutOpenFollowUpReturnsToLesson() {
        var state = PostPresentationFlowState()
        state.beginReflection()

        state.reflectionDidDismiss(
            presentationIsRecorded: true,
            hasOpenFollowUp: false
        )

        #expect(state.phase == .lesson)
        #expect(!state.shouldDismissDetail)
    }

    @Test("Resolving one child leaves the other child's responsibility open")
    func resolutionIsPerChild() throws {
        let fixture = try makeFixture()
        let rows = try record(fixture)
        #expect(rows.count == 2)

        let firstStudentID = try #require(fixture.students.first?.id?.uuidString)
        let firstRow = try #require(rows.first { $0.studentID == firstStudentID })
        let secondRow = try #require(rows.first { $0.studentID != firstStudentID })
        let resolvedAt = fixture.presentedDay.addingTimeInterval(3_600)

        PresentationFollowUpService.resolve(
            .continueIndependentWork,
            row: firstRow,
            at: resolvedAt
        )

        #expect(!firstRow.hasOpenFollowUp)
        #expect(firstRow.followUpResolution == .continueIndependentWork)
        #expect(firstRow.followUpResolvedAt == resolvedAt)
        #expect(secondRow.hasOpenFollowUp)
        #expect(secondRow.followUpResolution == nil)
        #expect(secondRow.followUpResolvedAt == nil)
    }

    @Test("Retrying an already-recorded presentation does not reopen a resolved follow-up")
    func idempotentRetryPreservesResolution() throws {
        let fixture = try makeFixture()
        let rows = try record(fixture)
        let firstStudentID = try #require(fixture.students.first?.id?.uuidString)
        let resolvedRow = try #require(rows.first { $0.studentID == firstStudentID })
        let resolvedAt = fixture.presentedDay.addingTimeInterval(7_200)
        PresentationFollowUpService.resolve(
            .noFurtherFollowUp,
            row: resolvedRow,
            at: resolvedAt
        )
        try fixture.context.save()

        _ = try ImmediatePresentationRecordingService.record(
            assignment: fixture.assignment,
            presentedOn: fixture.presentedDay,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )

        let assignmentID = try #require(fixture.assignment.id)
        let retriedRows = PresentationFollowUpService.rows(
            for: assignmentID,
            in: fixture.context
        )
        let retriedResolvedRow = try #require(
            retriedRows.first { $0.studentID == firstStudentID }
        )
        let openRowCount = retriedRows.reduce(into: 0) { count, row in
            if row.hasOpenFollowUp { count += 1 }
        }

        #expect(retriedRows.count == 2)
        #expect(!retriedResolvedRow.hasOpenFollowUp)
        #expect(retriedResolvedRow.followUpResolution == .noFurtherFollowUp)
        #expect(retriedResolvedRow.followUpResolvedAt == resolvedAt)
        #expect(openRowCount == 1)
    }

    @Test("Check-work dates are day-safe and changing paths clears stale details")
    func actionChangesKeepOneConsistentBundle() throws {
        let fixture = try makeFixture()
        let row = try #require(try record(fixture).first)
        let reviewTime = fixture.presentedDay.addingTimeInterval(50_000)

        PresentationFollowUpService.setAction(
            .checkWork,
            for: [row],
            reviewAt: reviewTime
        )

        #expect(row.followUpAction == .checkWork)
        #expect(row.followUpReviewAt == AppCalendar.startOfDay(reviewTime))
        #expect(row.followUpSupport == nil)

        PresentationFollowUpService.setAction(
            .planSupport,
            for: [row],
            support: .confer
        )

        #expect(row.followUpAction == .planSupport)
        #expect(row.followUpReviewAt == nil)
        #expect(row.followUpSupport == .confer)
    }

    @Test("Objective evidence and a factual note save without forcing an outcome")
    func observationCanRemainOpen() throws {
        let fixture = try makeFixture()
        let row = try #require(try record(fixture).first)
        let observedAt = fixture.presentedDay.addingTimeInterval(7_200)

        PresentationFollowUpService.saveObservation(
            evidence: [.concentrated, .returnedOrRepeated],
            note: "  Repeated the full sequence twice.  ",
            for: row,
            now: observedAt
        )

        #expect(row.followUpEvidence == [.concentrated, .returnedOrRepeated])
        #expect(row.followUpNote == "Repeated the full sequence twice.")
        #expect(row.lastObservedAt == observedAt)
        #expect(row.followUpResolution == nil)
        #expect(row.hasOpenFollowUp)
    }

    @Test("The shared queue groups children by presentation")
    func queueGroupsChildrenByPresentation() throws {
        let fixture = try makeFixture()
        let rows = try record(fixture)

        let allGroups = FollowingPresentationsService.groups(
            rows: rows,
            assignments: [fixture.assignment],
            lessons: [fixture.lesson],
            students: fixture.students,
            context: fixture.context,
            asOf: fixture.presentedDay
        )

        #expect(allGroups.count == 1)
        #expect(allGroups.first?.id == fixture.assignment.id)
        #expect(allGroups.first?.lessonName == "Golden Beads")
        #expect(allGroups.first?.children.count == 2)
        #expect(allGroups.first?.actionSummary == "Keep Watching")
    }

    @Test("The shared queue removes a synced duplicate child row")
    func queueDeduplicatesLogicalChildRows() throws {
        let fixture = try makeFixture()
        let rows = try record(fixture)
        let original = try #require(rows.first)
        let duplicate = CDLessonPresentation(context: fixture.context)
        duplicate.presentationID = original.presentationID
        duplicate.lessonID = original.lessonID
        duplicate.studentID = original.studentID
        duplicate.presentedAt = original.presentedAt
        duplicate.followUpAction = .watchWork
        duplicate.followUpUpdatedAt = fixture.presentedDay.addingTimeInterval(60)

        let groups = FollowingPresentationsService.groups(
            rows: rows + [duplicate],
            assignments: [fixture.assignment],
            lessons: [fixture.lesson],
            students: fixture.students,
            context: fixture.context,
            asOf: fixture.presentedDay
        )

        #expect(groups.count == 1)
        #expect(groups.first?.children.count == 2)
    }

    @Test("The shared queue filters by child and search text")
    func queueFiltersByStudentAndSearch() throws {
        let fixture = try makeFixture()
        let rows = try record(fixture)
        let firstStudentID = try #require(fixture.students.first?.id)

        let studentGroups = FollowingPresentationsService.groups(
            rows: rows,
            assignments: [fixture.assignment],
            lessons: [fixture.lesson],
            students: fixture.students,
            studentID: firstStudentID,
            context: fixture.context,
            asOf: fixture.presentedDay
        )
        #expect(studentGroups.count == 1)
        #expect(studentGroups.first?.children.count == 1)
        #expect(studentGroups.first?.children.first?.studentName == "Ada S")

        let matchingSearch = FollowingPresentationsService.groups(
            rows: rows,
            assignments: [fixture.assignment],
            lessons: [fixture.lesson],
            students: fixture.students,
            searchText: "Ada",
            context: fixture.context,
            asOf: fixture.presentedDay
        )
        let missingSearch = FollowingPresentationsService.groups(
            rows: rows,
            assignments: [fixture.assignment],
            lessons: [fixture.lesson],
            students: fixture.students,
            searchText: "Pink Tower",
            context: fixture.context,
            asOf: fixture.presentedDay
        )
        #expect(matchingSearch.count == 1)
        #expect(missingSearch.isEmpty)
    }
}
