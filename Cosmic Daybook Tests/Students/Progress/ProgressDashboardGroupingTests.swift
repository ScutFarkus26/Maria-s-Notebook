import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The dashboard groups assignments by student once instead of filtering
/// every assignment per student; the slices must be the same rows in the
/// same order.
@Suite("Progress dashboard grouping")
@MainActor
struct ProgressDashboardGroupingTests {

    @Test("groupByStudent equals the per-student filter it replaced")
    func groupingMatchesPerStudentFilter() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let students = (0..<4).map { index in
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Child\(index)")
        }
        let ids = try students.map { try #require($0.id).uuidString }
        let rosters: [[String]] = [
            [ids[0], ids[1]], [ids[1]], [ids[2], ids[0], ids[2]], [], [ids[3], ids[1], ids[0]]
        ]
        for roster in rosters {
            let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [], context: context)
            assignment.studentIDs = roster
        }
        #expect(CoreDataTestHelpers.save(context))

        let assignments = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        let grouped = ProgressDashboardViewModel.groupByStudent(assignments)
        for id in ids + [UUID().uuidString] {
            let filtered = assignments.filter { $0.studentIDs.contains(id) }
            #expect((grouped[id] ?? []).map(\.objectID) == filtered.map(\.objectID))
        }
        #expect(grouped[ids[0]]?.count == 3)
    }
}
