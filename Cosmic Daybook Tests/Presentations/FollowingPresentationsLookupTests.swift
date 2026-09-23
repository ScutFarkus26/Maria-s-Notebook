import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `FollowingPresentationsView` builds its groups from the assignments the
/// rows name and the live catalog's / roster's `byID`, instead of three
/// whole-table arrays. These pin that both paths give the same groups.
@Suite("Following presentations lookups")
@MainActor
struct FollowingPresentationsLookupTests {

    private struct Snapshot: Equatable {
        let id: UUID
        let assignment: NSManagedObjectID?
        let lessonName: String
        let presentedAt: Date
        let childNames: String
        let actionSummary: String
        let schoolDays: Int
    }

    private func snapshot(_ groups: [FollowingPresentationGroup]) -> [Snapshot] {
        groups.map {
            Snapshot(
                id: $0.id, assignment: $0.assignment?.objectID, lessonName: $0.lessonName,
                presentedAt: $0.presentedAt, childNames: $0.childNames,
                actionSummary: $0.actionSummary, schoolDays: $0.schoolDaysSincePresentation
            )
        }
    }

    @Test("Referenced assignments and byID lookups give the same groups as whole tables")
    func narrowedLookupsMatchWholeTables() throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true

        let beads = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", area: "Math", sequence: "Decimal")
        let stamps = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Decimal")
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Stone")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Hart")
        let cy = CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy", lastName: "Lee")
        let day = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 801_234_567))
        let first = PresentationFactory.makeScheduled(
            lesson: beads, students: [ada, ben], scheduledFor: day.addingTimeInterval(-86_400), context: context
        )
        let second = PresentationFactory.makeScheduled(
            lesson: stamps, students: [cy], scheduledFor: day.addingTimeInterval(-86_400), context: context
        )
        // An assignment no follow-up row names.
        _ = PresentationFactory.makeScheduled(
            lesson: stamps, students: [ada], scheduledFor: day, context: context
        )
        try context.save()
        for assignment in [first, second] {
            _ = try ImmediatePresentationRecordingService.record(
                assignment: assignment, presentedOn: day, context: context, saveCoordinator: coordinator
            )
        }
        // A row whose presentation is gone: the lesson name must come from the catalog.
        let orphan = CDLessonPresentation(context: context)
        orphan.id = UUID()
        orphan.presentationID = UUID().uuidString
        orphan.lessonID = try #require(beads.id).uuidString
        orphan.studentID = try #require(cy.id).uuidString
        orphan.presentedAt = day.addingTimeInterval(-3 * 86_400)
        orphan.followUpAction = .watchWork
        try context.save()

        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "followUpActionRaw != nil AND followUpResolvedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonPresentation.presentedAt, ascending: true)]
        let rows = context.safeFetch(request)
        #expect(rows.count == 4)

        let whole = FollowingPresentationsService.groups(
            rows: rows,
            assignments: context.safeFetch(CDFetchRequest(CDLessonAssignment.self)),
            lessons: dependencies.lessonCatalog.all,
            students: dependencies.roster.all,
            context: context,
            asOf: day
        )
        let referenced = FollowingPresentationsService.assignmentsReferenced(by: rows, in: context)
        #expect(Set(referenced.keys) == Set([try #require(first.id), try #require(second.id)]))
        let narrowed = FollowingPresentationsService.groups(
            rows: rows,
            assignmentByID: referenced,
            lessonByID: dependencies.lessonCatalog.byID,
            studentByID: dependencies.roster.byID,
            context: context,
            asOf: day
        )

        #expect(whole.count == 3)
        #expect(snapshot(narrowed) == snapshot(whole))

        let adaID = try #require(ada.id)
        let wholeForAda = FollowingPresentationsService.groups(
            rows: rows, assignments: context.safeFetch(CDFetchRequest(CDLessonAssignment.self)),
            lessons: dependencies.lessonCatalog.all, students: dependencies.roster.all,
            studentID: adaID, searchText: "beads", context: context, asOf: day
        )
        let narrowedForAda = FollowingPresentationsService.groups(
            rows: rows, assignmentByID: referenced,
            lessonByID: dependencies.lessonCatalog.byID, studentByID: dependencies.roster.byID,
            studentID: adaID, searchText: "beads", context: context, asOf: day
        )
        #expect(wholeForAda.count == 1)
        #expect(snapshot(narrowedForAda) == snapshot(wholeForAda))
    }
}
