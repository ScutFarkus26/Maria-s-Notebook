import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Student Departure Plans")
@MainActor
struct StudentDeparturePlansTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    @discardableResult
    private func seedPlan(
        in context: NSManagedObjectContext, lesson: CDLesson, students: [CDStudent],
        scheduledFor: Date? = nil, presented: Bool = false
    ) -> CDLessonAssignment {
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: students, context: context)
        if let scheduledFor {
            plan.schedule(for: scheduledFor, using: AppCalendar.shared)
        }
        if presented {
            plan.markPresented(at: Date())
        }
        return plan
    }

    @Test("future plans are the lessons not yet given that name her, soonest first")
    func futurePlansAreUngivenLessonsNamingHer() throws {
        let context = try makeContext()
        let naomi = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Levin")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let fractions = CoreDataTestHelpers.seedLesson(in: context, name: "Fractions")
        let needs = CoreDataTestHelpers.seedLesson(in: context, name: "Fundamental Needs")
        let history = CoreDataTestHelpers.seedLesson(in: context, name: "Timeline of Life")

        let later = seedPlan(in: context, lesson: fractions, students: [naomi, ora],
                             scheduledFor: Date().addingTimeInterval(14 * 86_400))
        let sooner = seedPlan(in: context, lesson: needs, students: [naomi],
                              scheduledFor: Date().addingTimeInterval(2 * 86_400))
        let draft = seedPlan(in: context, lesson: history, students: [naomi])
        seedPlan(in: context, lesson: fractions, students: [naomi], presented: true)
        seedPlan(in: context, lesson: needs, students: [ora])
        CoreDataTestHelpers.save(context)

        let plans = StudentDeparturePlans.futurePlans(for: try #require(naomi.id), in: context)
        #expect(plans.map(\.objectID) == [sooner, later, draft].map(\.objectID))
        #expect(StudentDeparturePlans.describe(draft, in: context) == "Timeline of Life — not yet scheduled")
        #expect(StudentDeparturePlans.describe(sooner, in: context).hasPrefix("Fundamental Needs — "))
    }

    @Test("retracting takes her off shared plans and deletes plans that named only her")
    func retractEditsAndDeletes() throws {
        let context = try makeContext()
        let naomi = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Levin")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Fractions")
        let shared = seedPlan(in: context, lesson: lesson, students: [naomi, ora])
        let solo = seedPlan(in: context, lesson: lesson, students: [naomi])
        let given = seedPlan(in: context, lesson: lesson, students: [naomi, ora], presented: true)
        CoreDataTestHelpers.save(context)
        let naomiID = try #require(naomi.id)

        let plans = StudentDeparturePlans.futurePlans(for: naomiID, in: context)
        let result = StudentDeparturePlans.retract(studentID: naomiID, from: plans, in: context)
        CoreDataTestHelpers.save(context)

        #expect(result == .init(plansEdited: 1, plansDeleted: 1))
        #expect(shared.studentUUIDs == [try #require(ora.id)])
        #expect(solo.isDeleted || solo.managedObjectContext == nil)
        // History is never edited.
        #expect(given.studentUUIDs.contains(naomiID))
        #expect(StudentDeparturePlans.futurePlans(for: naomiID, in: context).isEmpty)
    }

    @Test("rollover takes departing children off their future plans and counts them")
    func rolloverRetractsFuturePlans() throws {
        let context = try makeContext()
        let leaving = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Levin")
        let staying = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Fractions")
        let shared = seedPlan(in: context, lesson: lesson, students: [leaving, staying])
        seedPlan(in: context, lesson: lesson, students: [staying])
        CoreDataTestHelpers.save(context)

        var plan = RolloverPlan(effectiveDate: Date(), writeNotes: false)
        plan.outcomes[try #require(leaving.id)] = .withdraw

        let summary = RolloverService.summary(for: plan, students: [leaving, staying], context: context)
        #expect(summary.futurePlansForDeparting == 1)

        RolloverService.apply(plan, students: [leaving, staying], incomingYearLabel: "2026–2027", context: context)

        #expect(leaving.isWithdrawn)
        #expect(shared.studentUUIDs == [try #require(staying.id)])
        #expect(StudentDeparturePlans.futurePlans(for: try #require(staying.id), in: context).count == 2)
    }
}
