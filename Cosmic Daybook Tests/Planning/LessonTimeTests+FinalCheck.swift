import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `LessonTimeTests` for the paths the final check's review found (plan
/// "Lesson times on cards", Phase 5): a merge keeps a set time, MCP's
/// `time: "none"` with a new day keeps an untimed plan's half, and the year
/// plan never turns a lesson's clock time into a set time.
extension LessonTimeTests {

    // MARK: - Merging keeps a set time (decision 5)

    @Test("Merging a timed card into an untimed one gives it the time, on its own day")
    func mergeCarriesSetTime() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let thursday = day(2026, 9, 17)
        let source = planned(at: DayHalfPlanner.settingTime(hour: 10, minute: 15, on: wednesday), in: context)
        let target = planned(at: time(9, 0, 2, on: thursday), in: context)

        PresentationMergeService.carrySetTime(from: source, to: target)
        #expect(target.scheduledFor == DayHalfPlanner.settingTime(hour: 10, minute: 15, on: thursday))
        #expect(target.scheduledForDay == thursday)
    }

    @Test("A merge keeps the target's own time, and an untimed source changes nothing")
    func mergeKeepsTargetTime() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let timedSource = planned(at: DayHalfPlanner.settingTime(hour: 10, minute: 15, on: wednesday), in: context)
        let timedTarget = planned(at: DayHalfPlanner.settingTime(hour: 9, minute: 0, on: wednesday), in: context)
        let before = timedTarget.scheduledFor
        PresentationMergeService.carrySetTime(from: timedSource, to: timedTarget)
        #expect(timedTarget.scheduledFor == before)

        let slotSource = planned(at: time(14, 0, 1, on: wednesday), in: context)
        let slotTarget = planned(at: time(9, 0, 4, on: wednesday), in: context)
        PresentationMergeService.carrySetTime(from: slotSource, to: slotTarget)
        #expect(slotTarget.scheduledFor == time(9, 0, 4, on: wednesday))
    }

    // MARK: - MCP: "none" with a new day

    @Test("MCP: \"none\" with a new day keeps an untimed afternoon plan in the afternoon")
    func mcpNoneKeepsUntimedHalf() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bank Game", area: "Math", sequence: "Operations")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Katz")
        CoreDataTestHelpers.save(context)

        _ = try await tool("schedule_presentation", in: tools).handler([
            "lesson": .string("Bank Game"),
            "student_names": .array([.string("Noa")]),
            "date": .string("2026-09-16")
        ])
        let plan = try #require(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).first)
        plan.schedule(for: time(14, 0, 2, on: wednesday))
        CoreDataTestHelpers.save(context)
        let id = try #require(plan.id).uuidString

        let moved = try await tool("reschedule_presentation", in: tools).handler([
            "presentation_id": .string(id), "date": .string("2026-09-17"), "time": .string("none")
        ])
        #expect(moved.contains("now scheduled for 2026-09-17 in the afternoon."))
        #expect(DayHalfPlanner.moment(of: try #require(plan.scheduledFor)) == .half(.afternoon))
    }

    // MARK: - The year plan stores days, not times

    @Test("MCP: rescheduling a timed plan moves its year-plan entries to the day only")
    func mcpRescheduleMovesEntriesToTheDay() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bank Game", area: "Math", sequence: "Operations")
        let noa = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Katz")
        CoreDataTestHelpers.save(context)

        _ = try await tool("schedule_presentation", in: tools).handler([
            "lesson": .string("Bank Game"),
            "student_names": .array([.string("Noa")]),
            "date": .string("2026-09-16"),
            "time": .string("10:00")
        ])
        let plan = try #require(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).first)
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(noa.id).uuidString
        entry.lessonID = plan.lessonID
        entry.status = .promoted
        entry.promotedAssignmentID = try #require(plan.id).uuidString
        entry.plannedDate = wednesday
        CoreDataTestHelpers.save(context)

        _ = try await tool("reschedule_presentation", in: tools).handler([
            "presentation_id": .string(try #require(plan.id).uuidString), "date": .string("2026-09-17")
        ])
        #expect(DayHalfPlanner.setMinute(of: plan.scheduledFor) == 10 * 60)
        #expect(entry.plannedDate == day(2026, 9, 17))
    }

    @Test("Auto-promoting from a year-plan entry that carries a clock time sets no time")
    func autoPromoteSetsNoTime() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let studentID = UUID()
        let lessonID = UUID().uuidString
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: Date()))!
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = studentID.uuidString
        entry.lessonID = lessonID
        entry.status = .planned
        entry.plannedDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextWeek)

        let draft = planned(at: nil, in: context)
        draft.lessonID = lessonID
        draft.studentIDs = [studentID.uuidString]

        YearPlanPromotionService.autoPromoteIfPlanExists(assignment: draft, context: context)
        let scheduled = try #require(draft.scheduledFor)
        #expect(calendar.isDate(scheduled, inSameDayAs: nextWeek))
        #expect(DayHalfPlanner.isSetTime(scheduled) == false)
        #expect(DayHalfPlanner.moment(of: scheduled) == .half(.morning))
    }
}
