import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A lesson row's "Mark Presented Now" records only the children who were
/// there; one marked absent today stays on the plan.
@Suite("Today: Mark Presented Now")
@MainActor
struct TodayMarkPresentedTests {

    @Test("An absent child is not recorded and stays on a plan of her own")
    func absentChildStaysOnPlan() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game", area: "Math", sequence: "Operations"
        )
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya")
        let theo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Theo")
        let mayaID = try #require(maya.id)
        let theoID = try #require(theo.id)
        let today = AppCalendar.startOfDay(Date())
        CoreDataTestHelpers.seedAttendance(in: context, studentID: theoID, date: today).status = .absent
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [maya, theo], scheduledFor: today, context: context
        )
        try context.save()

        let result = try TodayMarkPresented.record(assignment, context: context, saveCoordinator: coordinator)

        #expect(result.keptOnPlan == [theoID])
        #expect(assignment.isPresented)
        #expect(assignment.resolvedStudentIDs == [mayaID])
        let history = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        #expect(history.map(\.studentID) == [mayaID.uuidString])

        let lessonID = try #require(lesson.id)
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        let plans = context.safeFetch(request).filter { $0 !== assignment }
        #expect(plans.map(\.resolvedStudentIDs) == [[theoID]])
        #expect(plans.first?.isPresented == false)
    }

    @Test("The toast names who stays on the plan")
    func message() {
        #expect(TodayMarkPresented.message(keptOnPlan: []) == "Marked presented")
        #expect(
            TodayMarkPresented.message(keptOnPlan: ["Theo S"])
                == "Marked presented. Theo S was absent and stays on the plan."
        )
    }
}
