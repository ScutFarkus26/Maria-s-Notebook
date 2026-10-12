import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11, #10–#14: a time set through Claude survives a
/// rearranged day, follow-ups leave with the child, "given earlier, date not
/// recorded" takes the children off their other plans, Suggest stops rewarding
/// a lesson whose children are all booked, and an undated presentation doesn't
/// make a child read as just taught.
@Suite("Presentations (bug hunt 2026-10-11)")
@MainActor
struct PresentationsFix1011PrTests {

    private let calendar = AppCalendar.shared

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0, on day: Date) throws -> Date {
        try #require(calendar.date(bySettingHour: hour, minute: minute, second: second, of: day))
    }

    // MARK: - #10 A time set through Claude

    @Test("Balancing a day leaves a card set to 10:30 at 10:30")
    func balanceKeepsASetTime() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let other = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let ana = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Hart")
        let day = try CoreDataTestHelpers.day("2026-10-14")
        let first = PresentationFactory.makeScheduled(
            lesson: lesson, students: [maya], scheduledFor: try at(9, 0, 0, on: day), context: context
        )
        let second = PresentationFactory.makeScheduled(
            lesson: other, students: [maya], scheduledFor: try at(9, 0, 1, on: day), context: context
        )
        let tenThirty = try at(10, 30, on: day)
        let timed = PresentationFactory.makeScheduled(
            lesson: other, students: [ana], scheduledFor: tenThirty, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let result = try #require(DayBalanceService.balance(
            day: day,
            assignments: [first, second, timed].sorted(by: LessonAssignmentOrdering.isOrderedBefore),
            calendar: calendar,
            context: context
        ))

        #expect(result.movedCount == 1)
        #expect(timed.scheduledFor == tenThirty)
        // The clash itself was still cleared around it.
        let halves = [first, second].compactMap(\.scheduledFor).map { DayPeriod(scheduledFor: $0) }
        #expect(Set(halves) == [.morning, .afternoon])
    }

    @Test("Numbering a day skips a kept time and numbers the slots around it")
    func numberingSkipsAKeptTime() throws {
        let day = try CoreDataTestHelpers.day("2026-10-14")
        let tenThirty = try at(10, 30, on: day)
        let first = UUID(), timed = UUID(), second = UUID()
        let slot = try at(9, 0, 3, on: day)
        #expect(DayHalfPlanner.keptTime(of: tenThirty) == tenThirty)
        #expect(DayHalfPlanner.keptTime(of: slot) == nil)
        #expect(DayHalfPlanner.keptTime(of: nil) == nil)

        let times = DayHalfPlanner.times(
            for: [
                .init(id: first, period: .morning),
                .init(id: timed, period: .morning, keptTime: tenThirty),
                .init(id: second, period: .morning)
            ],
            on: day,
            using: calendar,
            spacingSeconds: 1
        )

        let nine = try at(9, 0, 0, on: day)
        #expect(times[timed] == tenThirty)
        #expect(times[first] == nine)
        // A slot after the kept time counts on from it, so it still draws
        // below the 10:30 card (review 2026-10-11 (c) #5).
        #expect(times[second] == tenThirty.addingTimeInterval(1))
    }

    // MARK: - #11 Follow-ups for children who left

    @Test("A follow-up for a child not on the visible roster is left out, not shown as \"Child\"")
    func followUpsSkipChildrenOffTheRoster() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Stone")
        let left = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Bea", lastName: "Gone", enrollmentStatus: .withdrawn
        )
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [ada, left], context: context)
        _ = try LifecycleService.recordPresentation(
            from: assignment, presentedAt: try CoreDataTestHelpers.day("2026-10-01"), modelContext: context
        )
        #expect(CoreDataTestHelpers.save(context))
        let rows = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.hasOpenFollowUp })

        // The Follow Up pill hands over the visible enrolled roster.
        let groups = FollowingPresentationsService.groups(
            rows: rows,
            assignments: [assignment],
            lessons: [lesson],
            students: [ada],
            context: context
        )

        #expect(groups.count == 1)
        #expect(groups.first?.childNames == ada.shortName)
    }

    @Test("A group whose only child left disappears")
    func followUpGroupOfOnlyDepartedChildrenDisappears() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Stone")
        let left = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Bea", lastName: "Gone", enrollmentStatus: .withdrawn
        )
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [left], context: context)
        _ = try LifecycleService.recordPresentation(
            from: assignment, presentedAt: try CoreDataTestHelpers.day("2026-10-01"), modelContext: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let groups = FollowingPresentationsService.groups(
            rows: context.safeFetch(CDFetchRequest(CDLessonPresentation.self)),
            assignments: [assignment],
            lessons: [lesson],
            students: [ada],
            context: context
        )

        #expect(groups.isEmpty)
    }

    // MARK: - #12 Given earlier, date not recorded

    private func detailViewModel(for assignment: CDLessonAssignment, in context: NSManagedObjectContext)
        -> PresentationDetailViewModel {
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        return PresentationDetailViewModel(
            lessonAssignment: assignment, viewContext: context, saveCoordinator: coordinator
        )
    }

    @Test("Marking a plan given earlier, undated, takes its children off another plan for that lesson")
    func undatedGivingReleasesOtherPlans() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Skip Counting")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Singer")
        let toba = CoreDataTestHelpers.seedStudent(in: context, firstName: "Toba", lastName: "Fleischmann")
        let thursday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [maya, toba],
            scheduledFor: Date().addingTimeInterval(3 * 86_400), context: context
        )
        for student in [maya, toba] {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = try #require(student.id).uuidString
            entry.lessonID = try #require(lesson.id).uuidString
            entry.status = .promoted
            entry.promotedAssignmentID = try #require(thursday.id).uuidString
        }
        let earlier = PresentationFactory.makeDraft(lesson: lesson, students: [maya], context: context)
        #expect(CoreDataTestHelpers.save(context))

        let vm = detailViewModel(for: earlier, in: context)
        vm.isPresented = true
        vm.givenAt = nil
        vm.save(
            studentsAll: [maya, toba], lessons: [lesson],
            lessonAssignmentsAll: [thursday, earlier], calendar: calendar
        )

        #expect(earlier.isGiven)
        #expect(earlier.presentedAt == nil)
        let tobaID = try #require(toba.id).uuidString
        #expect(thursday.studentIDs == [tobaID])
    }

    @Test("Marking a plan given earlier, undated, returns entries promoted into it for another lesson")
    func undatedGivingReturnsOtherLessonsEntries() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let other = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [ada], context: context)
        // Promoted into this plan while it was still the Stamp Game.
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(ada.id).uuidString
        entry.lessonID = try #require(other.id).uuidString
        entry.status = .promoted
        entry.promotedAssignmentID = try #require(plan.id).uuidString
        #expect(CoreDataTestHelpers.save(context))

        let vm = detailViewModel(for: plan, in: context)
        vm.isPresented = true
        vm.givenAt = nil
        vm.save(studentsAll: [ada], lessons: [lesson, other], lessonAssignmentsAll: [plan], calendar: calendar)

        #expect(entry.status == .planned)
        #expect(entry.promotedAssignmentID == nil)
    }

    // MARK: - #13 Suggest

    @Test("A lesson whose children are all booked gets no open-work bonus")
    func noOpenWorkBonusWhenEveryoneIsBooked() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let booked = UUID()
        let waiting = UUID()
        let lessonID = UUID()
        let tomorrow = AppCalendar.startOfDay(Date()).addingTimeInterval(86_400 + 9 * 3_600)
        let booking = PresentationFactory.makeScheduled(
            lessonID: UUID(), studentIDs: [booked], scheduledFor: tomorrow, context: context
        )
        let allBooked = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [booked], context: context)
        let hasAWait = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [waiting], context: context)

        let vm = PresentationsViewModel()
        vm.daysSinceLastLessonByStudent = [booked: 0, waiting: 1]
        vm.openWorkCountByStudent = [booked: 0, waiting: 4]

        let ranked = vm.rankedSuggestions(
            among: [allBooked, hasAWait], allLessonAssignments: [booking, allBooked, hasAWait]
        )

        #expect(ranked.map(\.assignment) == [hasAWait, allBooked])
        #expect(ranked.last?.rationale.everyoneAlreadyScheduled == true)
    }

    @Test("A missed lesson from yesterday doesn't count as booked, as on the Waiting rail")
    func missedPastLessonIsNotABooking() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        let yesterday = AppCalendar.startOfDay(Date()).addingTimeInterval(-86_400 + 9 * 3_600)
        let missed = PresentationFactory.makeScheduled(
            lessonID: UUID(), studentIDs: [child], scheduledFor: yesterday, context: context
        )
        let candidate = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [child], context: context)
        #expect(WaitingStudentsOrder.studentIDsWithUpcomingLessons(in: [missed]).isEmpty)

        let vm = PresentationsViewModel()
        vm.daysSinceLastLessonByStudent = [child: 6]

        let ranked = vm.rankedSuggestions(among: [candidate], allLessonAssignments: [missed, candidate])

        let rationale = try #require(ranked.first?.rationale)
        #expect(!rationale.everyoneAlreadyScheduled)
        #expect(rationale.waitingSchoolDays == 6)
    }

    // MARK: - #14 Undated presentations

    @Test("An undated earlier presentation doesn't make a child read as taught today")
    func undatedPresentationIsSkippedForLastTaught() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", area: "Math")
        let earlier = CoreDataTestHelpers.seedLesson(in: context, name: "Spindle Box", area: "Language")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let mayaID = try #require(maya.id)
        let dated = try CoreDataTestHelpers.day("2026-09-14")
        let given = PresentationFactory.makePresented(
            lessonID: try #require(lesson.id), studentIDs: [mayaID], presentedAt: dated, context: context
        )
        // Marked "given earlier" today: no date, created now.
        let undated = PresentationFactory.makeDraft(lesson: earlier, students: [maya], context: context)
        undated.markPreviouslyPresented()
        #expect(CoreDataTestHelpers.save(context))

        let vm = PresentationsViewModel()
        vm.viewContext = context
        vm.calculateDaysSinceLastLesson(
            lessonAssignments: [given, undated], lessons: [lesson, earlier], students: [maya]
        )

        let expected = LessonAgeHelper.schoolDaysSinceCreation(createdAt: dated, using: context)
        #expect(expected > 0)
        #expect(vm.daysSinceLastLessonByStudent[mayaID] == expected)
        #expect(vm.lastAreaByStudent[mayaID] == "Math")
    }

    @Test("A child whose only presentations are undated reads as never taught, not taught today")
    func onlyUndatedPresentationsReadAsNeverTaught() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Spindle Box")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let undated = PresentationFactory.makeDraft(lesson: lesson, students: [maya], context: context)
        undated.markPreviouslyPresented()
        #expect(CoreDataTestHelpers.save(context))

        let vm = PresentationsViewModel()
        vm.viewContext = context
        vm.calculateDaysSinceLastLesson(lessonAssignments: [undated], lessons: [lesson], students: [maya])

        let mayaID = try #require(maya.id)
        #expect(vm.daysSinceLastLessonByStudent[mayaID] == Int.max)
    }
}
