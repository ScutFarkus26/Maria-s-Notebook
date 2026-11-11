import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `LessonTimeTests` through the store: the entity's methods, Balance, Today,
/// the MCP tools and the shared order (plan "Lesson times on cards", Phase 1).
extension LessonTimeTests {

    // MARK: - Decision 5: the entity's methods

    @Test("setTime and removeTime go through the shared rules")
    func entitySetAndRemove() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let assignment = planned(at: time(9, 0, 2, on: wednesday), in: context)

        assignment.setTime(hour: 9, minute: 0)
        #expect(clock(assignment.scheduledFor) == [9, 0, 59])
        #expect(assignment.setTimeMinute() == 540)
        #expect(assignment.scheduledForDay == wednesday)

        assignment.setTime(hour: 13, minute: 30)
        #expect(assignment.setTimeMinute() == 13 * 60 + 30)

        assignment.removeTime()
        #expect(assignment.scheduledFor == time(14, 0, DayHalfPlanner.lastSlotRank, on: wednesday))
        #expect(assignment.setTimeMinute() == nil)

        // No day, no time.
        let unscheduled = planned(at: nil, in: context)
        unscheduled.setTime(hour: 10, minute: 0)
        #expect(unscheduled.scheduledFor == nil)
    }

    @Test("Moving to another day keeps a set time; a slot lands at the start of the morning")
    func entityMoveKeepsTime() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let thursday = day(2026, 9, 17)
        let timed = planned(at: DayHalfPlanner.settingTime(hour: 14, minute: 0, on: wednesday), in: context)
        let slot = planned(at: time(14, 0, 3, on: wednesday), in: context)

        timed.schedule(onDay: thursday, keepingTimeUsing: calendar)
        slot.schedule(onDay: thursday, keepingTimeUsing: calendar)

        #expect(timed.scheduledFor == DayHalfPlanner.settingTime(hour: 14, minute: 0, on: thursday))
        #expect(timed.scheduledForDay == thursday)
        #expect(slot.scheduledFor == time(9, 0, 0, on: thursday))
    }

    // MARK: - Decision 5: Balance

    @Test("Balance never moves a timed lesson, and the others move around it")
    func balanceLeavesTimedLessons() {
        let maya = UUID()
        let timed = DayHalfBalancer.Booking(id: UUID(), period: .morning, studentIDs: [maya], isTimed: true)
        let other = DayHalfBalancer.Booking(id: UUID(), period: .morning, studentIDs: [maya])
        // The timed lesson is listed later, where the untimed balance would
        // have moved it.
        let outcome = DayHalfBalancer.balanced([other, timed])
        #expect(outcome.placements.first { $0.id == timed.id }?.period == .morning)
        #expect(outcome.placements.first { $0.id == other.id }?.period == .afternoon)
        #expect(outcome.unresolvedStudentIDs.isEmpty)
    }

    @Test("Two timed lessons sharing a child stay put and are reported")
    func balanceCannotMoveTwoTimedLessons() {
        let maya = UUID()
        let first = DayHalfBalancer.Booking(id: UUID(), period: .morning, studentIDs: [maya], isTimed: true)
        let second = DayHalfBalancer.Booking(id: UUID(), period: .morning, studentIDs: [maya], isTimed: true)
        let outcome = DayHalfBalancer.balanced([first, second])
        #expect(outcome.movedCount == 0)
        #expect(outcome.unresolvedStudentIDs == [maya])
    }

    @Test("Balancing a day through the store keeps an exact 9:00")
    func balanceThroughTheStoreKeepsNine() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let other = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let nine = DayHalfPlanner.settingTime(hour: 9, minute: 0, on: wednesday)
        let timed = PresentationFactory.makeScheduled(
            lesson: lesson, students: [maya], scheduledFor: nine, context: context
        )
        let slot = PresentationFactory.makeScheduled(
            lesson: other, students: [maya], scheduledFor: time(9, 0, 0, on: wednesday), context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let result = try #require(DayBalanceService.balance(
            day: wednesday,
            assignments: LessonAssignmentOrdering.sorted([slot, timed]),
            calendar: calendar,
            context: context
        ))
        #expect(result.movedToAfternoon == 1)
        #expect(timed.scheduledFor == nine)
        #expect(slot.scheduledFor.map { DayPeriod(scheduledFor: $0) } == .afternoon)
    }

    // MARK: - Decision 5: Today and MCP

    @Test("Moving absent children keeps the time on a lesson that moves whole")
    func absentMoveKeepsTime() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game", area: "Math", sequence: "Operations"
        )
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya")
        let today = calendar.startOfDay(for: Date())
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [maya],
            scheduledFor: DayHalfPlanner.settingTime(hour: 10, minute: 15, on: today), context: context
        )
        try context.save()

        let mayaID = try #require(maya.id)
        let receipt = try TodayAbsentMover.moveAbsent(
            from: [assignment], absent: [mayaID], to: tomorrow,
            context: context, saveCoordinator: coordinator
        )
        #expect(receipt != nil)
        #expect(assignment.scheduledFor == DayHalfPlanner.settingTime(hour: 10, minute: 15, on: tomorrow))
    }

    func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    func tool(_ name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    @Test("MCP: 09:00 and 14:00 stick, a new day keeps the time, and \"none\" removes it")
    func mcpTimes() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bank Game", area: "Math", sequence: "Operations")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Katz")
        CoreDataTestHelpers.save(context)

        let scheduled = try await tool("schedule_presentation", in: tools).handler([
            "lesson": .string("Bank Game"),
            "student_names": .array([.string("Noa")]),
            "date": .string("2026-09-16"),
            "time": .string("09:00")
        ])
        #expect(scheduled.contains("on 2026-09-16 at 09:00."))
        let plan = try #require(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).first)
        #expect(DayHalfPlanner.setMinute(of: plan.scheduledFor) == 9 * 60)
        let id = try #require(plan.id).uuidString

        let listing = try await tool("schedule_for_range", in: tools).handler([
            "start_date": .string("2026-09-16"), "end_date": .string("2026-09-16")
        ])
        #expect(listing.contains("Bank Game at 09:00"))

        let reschedule = try tool("reschedule_presentation", in: tools)
        let two = try await reschedule.handler(["presentation_id": .string(id), "time": .string("14:00")])
        #expect(two.contains("now at 14:00."))
        #expect(DayHalfPlanner.setMinute(of: plan.scheduledFor) == 14 * 60)

        let moved = try await reschedule.handler(["presentation_id": .string(id), "date": .string("2026-09-17")])
        #expect(moved.contains("now scheduled for 2026-09-17 at 14:00."))

        // schedule_presentation on the same plan, with no time, keeps it too.
        let again = try await tool("schedule_presentation", in: tools).handler([
            "lesson": .string("Bank Game"),
            "student_names": .array([.string("Noa")]),
            "date": .string("2026-09-18")
        ])
        #expect(again.contains("on 2026-09-18 at 14:00."))

        let removed = try await reschedule.handler(["presentation_id": .string(id), "time": .string("None")])
        #expect(removed.contains("now in the afternoon."))
        #expect(DayHalfPlanner.setMinute(of: plan.scheduledFor) == nil)

        // "none" with a date: the morning half of that day.
        _ = try await reschedule.handler(["presentation_id": .string(id), "time": .string("10:30")])
        let dated = try await reschedule.handler([
            "presentation_id": .string(id), "date": .string("2026-09-21"), "time": .string("none")
        ])
        #expect(dated.contains("now scheduled for 2026-09-21 in the morning."))

        // An afternoon time taken off with a new date stays in the afternoon.
        _ = try await reschedule.handler(["presentation_id": .string(id), "time": .string("14:30")])
        let afternoon = try await reschedule.handler([
            "presentation_id": .string(id), "date": .string("2026-09-22"), "time": .string("none")
        ])
        #expect(afternoon.contains("now scheduled for 2026-09-22 in the afternoon."))
    }

    // MARK: - Decision 6: the shared order

    @Test("Morning before afternoon; timed first by clock, then slots by rank")
    func sharedOrder() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let thursday = day(2026, 9, 17)
        let legacy = planned(at: wednesday, in: context)                                   // midnight
        let slotTwo = planned(at: time(9, 0, 2, on: wednesday), in: context)
        let slotZero = planned(at: time(9, 0, 0, on: wednesday), in: context)
        let pushed = planned(at: time(10, 30, 1, on: wednesday), in: context)               // old slot
        let tenThirty = planned(at: time(10, 30, on: wednesday), in: context)
        let nine = planned(at: DayHalfPlanner.settingTime(hour: 9, minute: 0, on: wednesday), in: context)
        let afternoonSlot = planned(at: time(14, 0, 0, on: wednesday), in: context)
        let quarterPastOne = planned(at: time(13, 15, on: wednesday), in: context)
        let nextDay = planned(at: time(9, 0, 0, on: thursday), in: context)
        let unscheduled = planned(at: nil, in: context)

        let mixed = [nextDay, afternoonSlot, pushed, slotTwo, tenThirty, unscheduled, quarterPastOne,
                     legacy, nine, slotZero]
        let expected = [unscheduled, nine, tenThirty, legacy, slotZero, slotTwo, pushed,
                        quarterPastOne, afternoonSlot, nextDay]
        #expect(LessonAssignmentOrdering.sorted(mixed).map(\.id) == expected.map(\.id))
        #expect(mixed.sorted(by: LessonAssignmentOrdering.isOrderedBefore).map(\.id) == expected.map(\.id))
    }

    @Test("Two lessons at the same minute fall back to the tie-breaks")
    func sameMinuteTieBreak() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = planned(at: time(10, 30, on: wednesday), in: context)
        let second = planned(at: time(10, 30, on: wednesday), in: context)
        second.createdAt = wednesday.addingTimeInterval(60)
        #expect(LessonAssignmentOrdering.sorted([second, first]).map(\.id) == [first.id, second.id])
    }

    @Test("Today's lessons come back in the shared order")
    func todayFetchUsesTheSharedOrder() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let slot = planned(at: time(9, 0, 0, on: wednesday), in: context)
        let timed = planned(at: time(10, 0, on: wednesday), in: context)
        let afternoon = planned(at: time(14, 0, 0, on: wednesday), in: context)
        for item in [slot, timed, afternoon] { item.lessonID = UUID().uuidString }
        #expect(CoreDataTestHelpers.save(context))

        let fetched: [CDLessonAssignment] = TodayDataFetcher.fetchLessons(
            day: wednesday, nextDay: day(2026, 9, 17), context: context
        )
        let fetchedIDs: [UUID?] = fetched.map(\.id)
        let expectedIDs: [UUID?] = [timed.id, slot.id, afternoon.id]
        #expect(fetchedIDs == expectedIDs)
    }
}
