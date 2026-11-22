import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The lesson loop over MCP (plan "Cut unused features and close the lesson
/// loop", Phase 3): `schedule_for_range` › `unrecorded`, `record_presentation`
/// with `planned_presentation_id`, the practice warnings, practice timing on
/// a filed presentation, quick notes, and titled work.
@Suite("MCP lesson loop tools")
@MainActor
struct MCPLessonLoopToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func call(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> String {
        try await #require(tools.first { $0.name == name }).handler(arguments)
    }

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    /// The first school day after today.
    private func nextSchoolDay(in context: NSManagedObjectContext) throws -> Date {
        try #require(SchoolDayChecker.schoolDay(from: Date(), forward: true, using: context))
    }

    private func lesson(
        _ name: String, step: Int, in context: NSManagedObjectContext
    ) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: "Math", sequence: "Multiplication")
        lesson.id = UUID()
        lesson.orderInSequence = Int64(step)
        return lesson
    }

    private func student(_ first: String, _ last: String, in context: NSManagedObjectContext) -> CDStudent {
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: first, lastName: last)
        student.id = UUID()
        return student
    }

    // MARK: - unrecorded

    @Test("unrecorded lists a past day's plan, not a given lesson, a quick note, and a No School day")
    func unrecordedListsWhatIsOpen() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let stamp = lesson("Stamp Game", step: 2, in: context)
        let ora = student("Ora", "Levi", in: context)
        let etty = student("Etty", "Klein", in: context)
        // Wednesday 2026-11-18: planned for Ora, never recorded.
        let left = PresentationFactory.makeDraft(lesson: golden, students: [ora], context: context)
        left.schedule(onDay: try day("2026-11-18"))
        // Thursday: planned for Etty and given.
        let given = PresentationFactory.makeDraft(lesson: stamp, students: [etty], context: context)
        given.schedule(onDay: try day("2026-11-19"))
        given.markPresented(at: try day("2026-11-19"))
        // A quick note on the given lesson.
        let quick = try #require(QuickNote.save(text: "Used the board", presentation: given, context: context))
        // Friday: an all-day "No School" event, school still counted in session.
        let event = CDCalendarEvent(context: context)
        event.id = UUID()
        event.title = "No School - Staff Day"
        event.isAllDay = true
        event.startDate = try day("2026-11-20")
        event.endDate = try day("2026-11-21")
        CoreDataTestHelpers.save(context)

        let output = try await call("schedule_for_range", [
            "view": .string("unrecorded"),
            "start_date": .string("2026-11-16"),
            "end_date": .string("2026-11-20")
        ], in: tools)

        #expect(output.contains("2026-11-18 (Wednesday)"))
        #expect(output.contains("[presentation id=\(try #require(left.id).uuidString)] Golden Beads — Ora L"))
        #expect(!output.contains("Stamp Game —"), "a given lesson is not open")
        let noteID = try #require(quick.id).uuidString
        #expect(output.contains("[note id=\(noteID)] \"Used the board\" — Etty K (Stamp Game)"))
        #expect(output.contains("\"No School - Staff Day\""))
        #expect(output.contains("set_school_days with date 2026-11-20"))
        #expect(output.contains("record_presentation with planned_presentation_id"))
        #expect(output.contains("update_observation"))
    }

    @Test("unrecorded says so when nothing is open")
    func unrecordedEmpty() async throws {
        let (tools, _) = try makeTools()
        let output = try await call("schedule_for_range", ["view": .string("unrecorded")], in: tools)
        #expect(output.contains("Nothing is open"))
    }

    @Test("unrecorded shows a child still practicing an earlier lesson")
    func unrecordedShowsPractice() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let stamp = lesson("Stamp Game", step: 2, in: context)
        let ora = student("Ora", "Levi", in: context)
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Practice", studentID: try #require(ora.id), lessonID: try #require(golden.id)
        )
        work.status = .active
        work.createdAt = try day("2026-11-02")
        PresentationFactory.makeDraft(lesson: stamp, students: [ora], context: context)
            .schedule(onDay: try day("2026-11-18"))
        CoreDataTestHelpers.save(context)

        let output = try await call("schedule_for_range", [
            "view": .string("unrecorded"), "start_date": .string("2026-11-18"), "end_date": .string("2026-11-18")
        ], in: tools)
        #expect(output.contains("Ora L still has practice open on Golden Beads (since Nov 2)."))
    }

    // MARK: - planned_presentation_id

    @Test("record_presentation with planned_presentation_id and a different group closes the plan")
    func recordTakesOverPlan() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let ora = student("Ora", "Levi", in: context)
        let etty = student("Etty", "Klein", in: context)
        let maya = student("Maya", "Soto", in: context)
        let plan = PresentationFactory.makeDraft(lesson: golden, students: [ora, etty], context: context)
        plan.schedule(onDay: try day("2026-11-18"))
        CoreDataTestHelpers.save(context)
        let planID = try #require(plan.id)

        // Ora and Maya were there; Etty wasn't.
        let output = try await call("record_presentation", [
            "planned_presentation_id": .string(planID.uuidString),
            "student_names": .array([.string("Ora"), .string("Maya")]),
            "date": .string("2026-11-18")
        ], in: tools)
        #expect(output.contains("Recorded the lesson planned for them"))

        let all = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        let given = try #require(all.first { $0.isGiven })
        #expect(Set(given.resolvedStudentIDs) == Set([ora.id, maya.id].compactMap { $0 }))
        let waiting = try #require(all.first { !$0.isGiven })
        #expect(waiting.resolvedStudentIDs == [try #require(etty.id)], "Etty stays planned")
        #expect(waiting.scheduledFor.map(AppCalendar.startOfDay) == (try day("2026-11-18")))
        #expect(all.count == 2)
    }

    @Test("record_presentation with planned_presentation_id and the whole group gives the plan itself")
    func recordGivesPlanItself() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let ora = student("Ora", "Levi", in: context)
        let maya = student("Maya", "Soto", in: context)
        let plan = PresentationFactory.makeDraft(lesson: golden, students: [ora], context: context)
        plan.schedule(onDay: try day("2026-11-18"))
        CoreDataTestHelpers.save(context)
        let planID = try #require(plan.id)

        _ = try await call("record_presentation", [
            "planned_presentation_id": .string(planID.uuidString),
            "lesson": .string("Golden Beads"),
            "student_names": .array([.string("Ora"), .string("Maya")]),
            "date": .string("2026-11-18")
        ], in: tools)
        let all = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        #expect(all.count == 1)
        #expect(plan.isGiven)
        #expect(Set(plan.resolvedStudentIDs) == Set([ora.id, maya.id].compactMap { $0 }))
    }

    @Test("planned_presentation_id is refused for another lesson, a given plan, or nobody on it")
    func plannedIDRefusals() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        _ = lesson("Stamp Game", step: 2, in: context)
        let ora = student("Ora", "Levi", in: context)
        _ = student("Maya", "Soto", in: context)
        let plan = PresentationFactory.makeDraft(lesson: golden, students: [ora], context: context)
        plan.schedule(onDay: try day("2026-11-18"))
        CoreDataTestHelpers.save(context)
        let planID = try #require(plan.id).uuidString

        await #expect(throws: MCPToolError.self) {
            try await call("record_presentation", [
                "planned_presentation_id": .string(planID), "lesson": .string("Stamp Game"),
                "student_names": .array([.string("Ora")])
            ], in: tools)
        }
        await #expect(throws: MCPToolError.self) {
            try await call("record_presentation", [
                "planned_presentation_id": .string(planID), "student_names": .array([.string("Maya")])
            ], in: tools)
        }
        await #expect(throws: MCPToolError.self) {
            try await call("record_presentation", [
                "presentations": .array([
                    .object(["planned_presentation_id": .string(planID), "student_names": .array([.string("Ora")])]),
                    .object(["planned_presentation_id": .string(planID), "student_names": .array([.string("Ora")])])
                ])
            ], in: tools)
        }
        plan.markPresented(at: try day("2026-11-18"))
        CoreDataTestHelpers.save(context)
        await #expect(throws: MCPToolError.self) {
            try await call("record_presentation", [
                "planned_presentation_id": .string(planID), "student_names": .array([.string("Ora")])
            ], in: tools)
        }
    }

    // MARK: - Warnings

    @Test("Scheduling, recording and adding a child warn about practice still open")
    func warningLines() async throws {
        let (tools, context) = try makeTools()
        let distributive = lesson("The Distributive Law", step: 1, in: context)
        let squares = lesson("Squaring", step: 2, in: context)
        let ora = student("Ora", "Levi", in: context)
        let maya = student("Maya", "Soto", in: context)
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Practice", studentID: try #require(ora.id), lessonID: try #require(distributive.id)
        )
        work.status = .active
        work.createdAt = try day("2026-11-02")
        CoreDataTestHelpers.save(context)
        let warning = "Ora L still has practice open on The Distributive Law (since Nov 2)."

        let scheduled = try await call("schedule_presentation", [
            "lesson": .string("Squaring"), "student_names": .array([.string("Maya")]),
            "date": .string(MCPNotebookTools.dayString(try nextSchoolDay(in: context)))
        ], in: tools)
        #expect(!scheduled.contains("still has practice"))
        let plans = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        let planID = try #require(plans.first { $0.lessonID == squares.id?.uuidString }?.id)

        let added = try await call("update_presentation_roster", [
            "presentation_id": .string(planID.uuidString), "add_students": .array([.string("Ora")])
        ], in: tools)
        #expect(added.contains(warning))

        let recorded = try await call("record_presentation", [
            "lesson": .string("Squaring"), "student_names": .array([.string("Ora"), .string("Maya")])
        ], in: tools)
        #expect(recorded.contains(warning))
        #expect(!recorded.contains("Maya S still"))
        _ = maya
    }

    // MARK: - Practice timing on a filed presentation

    @Test("Practice filed through chat gets a check-in the school day before the next planned lesson")
    func recordedPracticeComesBack() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let stamp = lesson("Stamp Game", step: 2, in: context)
        let ora = student("Ora", "Levi", in: context)
        let next = SchoolDayChecker.nextSchoolDays(
            from: AppCalendar.addingDays(1, to: Date()), count: 5, using: context
        )
        let lessonDay = try #require(next.last)
        PresentationFactory.makeDraft(lesson: stamp, students: [ora], context: context).schedule(onDay: lessonDay)
        CoreDataTestHelpers.save(context)

        _ = try await call("record_presentation", [
            "lesson": .string("Golden Beads"), "student_names": .array([.string("Ora")]),
            "student_observations": .array([.object([
                "student": .string("Ora"), "observation": .string("Wants more."), "follow_up": .string("practice")
            ])])
        ], in: tools)
        let work = try #require(context.safeFetch(CDFetchRequest(CDWorkModel.self)).first {
            $0.lessonID == golden.id?.uuidString
        })
        let checkIns = WorkLogService.scheduledCheckIns(of: work, in: context)
        #expect(checkIns.count == 1)
        #expect(checkIns.first?.date.map(AppCalendar.startOfDay) == next[3])
        #expect(work.title == "Practice: Golden Beads")
    }

}

extension MCPLessonLoopToolsTests {

    @Test("Two children filed together get their own check-in days")
    func recordedPracticeDaysPerChild() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let stamp = lesson("Stamp Game", step: 2, in: context)
        let ora = student("Ora", "Levi", in: context)
        let maya = student("Maya", "Stern", in: context)
        let next = SchoolDayChecker.nextSchoolDays(
            from: AppCalendar.addingDays(1, to: Date()), count: 5, using: context
        )
        let lessonDay = try #require(next.last)
        PresentationFactory.makeDraft(lesson: stamp, students: [ora], context: context).schedule(onDay: lessonDay)
        CoreDataTestHelpers.save(context)

        let practice: (String) -> JSONValue = { name in
            .object(["student": .string(name), "observation": .string("Wants more."), "follow_up": .string("practice")])
        }
        _ = try await call("record_presentation", [
            "lesson": .string("Golden Beads"), "student_names": .array([.string("Ora"), .string("Maya")]),
            "student_observations": .array([practice("Ora"), practice("Maya")])
        ], in: tools)
        let work = context.safeFetch(CDFetchRequest(CDWorkModel.self)).filter { $0.lessonID == golden.id?.uuidString }
        let day: (CDStudent) -> Date? = { child in
            work.first { $0.studentID == child.id?.uuidString }
                .flatMap { WorkLogService.scheduledCheckIns(of: $0, in: context).first?.date }
                .map(AppCalendar.startOfDay)
        }
        #expect(work.count == 2)
        #expect(day(ora) == next[3], "the school day before her Stamp Game")
        #expect(day(maya) == next[2], "three school days after, with nothing planned")
    }

    // MARK: - Quick notes

    @Test("Replacing a quick note's words takes the tag off")
    func updateObservationDropsTag() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let ora = student("Ora", "Levi", in: context)
        let given = PresentationFactory.makeDraft(lesson: golden, students: [ora], context: context)
        given.markPresented(at: Date())
        let note = try #require(QuickNote.save(text: "Board", presentation: given, context: context))
        #expect(QuickNote.isWaiting(note))
        #expect(note.lessonAssignment == given)
        #expect(note.scope == .student(try #require(ora.id)))

        _ = try await call("update_observation", [
            "note_id": .string(try #require(note.id).uuidString),
            "body": .string("Built the whole board alone."),
            "tags": .array([.string("to fill in"), .string("math")])
        ], in: tools)
        #expect(!QuickNote.isWaiting(note))
        #expect(note.tagsArray.contains { TagHelper.tagName($0).lowercased() == "math" })
    }

    // MARK: - Titles

    @Test("Work made without a title is named for its lesson, and a read prints the lesson for an empty one")
    func titledWork() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let ora = student("Ora", "Levi", in: context)
        let made = try WorkRepository(context: context).createWork(
            studentID: try #require(ora.id), lessonID: try #require(golden.id),
            kind: .practiceLesson, saveImmediately: false
        )
        #expect(made.title == "Practice: Golden Beads")

        let untitled = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "", studentID: try #require(ora.id), lessonID: try #require(golden.id)
        )
        untitled.id = UUID()
        CDWorkCheckIn.make(for: untitled, on: AppCalendar.startOfDay(Date()), in: context)
        CoreDataTestHelpers.save(context)
        let output = try await call("schedule_for_range", [:], in: tools)
        #expect(output.contains("[work id=\(try #require(untitled.id).uuidString)] Golden Beads"))
        #expect(!output.contains("Untitled work"))
    }
}
