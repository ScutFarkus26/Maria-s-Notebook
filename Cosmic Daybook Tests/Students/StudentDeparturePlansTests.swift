import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Student Departure Plans")
@MainActor
struct StudentDeparturePlansTests {

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
        let context = try CoreDataTestHelpers.makeContext()
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
        let context = try CoreDataTestHelpers.makeContext()
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
        #expect(shared.resolvedStudentIDs == [try #require(ora.id)])
        #expect(solo.isDeleted || solo.managedObjectContext == nil)
        // History is never edited.
        #expect(given.resolvedStudentIDs.contains(naomiID))
        #expect(StudentDeparturePlans.futurePlans(for: naomiID, in: context).isEmpty)
    }

    @Test("rollover takes departing children off their future plans and counts them")
    func rolloverRetractsFuturePlans() throws {
        let context = try CoreDataTestHelpers.makeContext()
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

        try RolloverService.apply(plan, students: [leaving, staying], incomingYearLabel: "2026–2027", context: context)

        #expect(leaving.isWithdrawn)
        #expect(shared.resolvedStudentIDs == [try #require(staying.id)])
        #expect(StudentDeparturePlans.futurePlans(for: try #require(staying.id), in: context).count == 2)
    }

    @Test("A rollover departure is the student page's: her open work closes once her last day has passed")
    func rolloverDepartureRunsTheWholeCascade() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let leaving = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Levin")
        let later = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let leavingID = try #require(leaving.id)
        let laterID = try #require(later.id)
        let past = CoreDataTestHelpers.seedWorkModel(in: context, title: "Fraction strips", studentID: leavingID)
        let ahead = CoreDataTestHelpers.seedWorkModel(in: context, title: "Fraction strips", studentID: laterID)
        CoreDataTestHelpers.save(context)
        let ledger = DepartureSkipLedger.inMemory()

        var gone = RolloverPlan(effectiveDate: AppCalendar.addingDays(-1, to: Date()), writeNotes: false)
        gone.outcomes[leavingID] = .withdraw
        try RolloverService.apply(
            gone, students: [leaving], incomingYearLabel: "2026–2027", context: context, ledger: ledger
        )
        #expect(past.status == .incomplete)
        #expect(!ledger.isOwed(leavingID))

        // Leaving on a day still ahead: her work waits, owed to the first launch after it.
        var soon = RolloverPlan(effectiveDate: AppCalendar.addingDays(3, to: Date()), writeNotes: false)
        soon.outcomes[laterID] = .transfer
        try RolloverService.apply(
            soon, students: [later], incomingYearLabel: "2026–2027", context: context, ledger: ledger
        )
        #expect(later.enrollmentStatus == .transferred)
        #expect(ahead.status == .active)
        #expect(ledger.isOwed(laterID))
    }
}
