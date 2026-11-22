import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Five lesson-loop gaps over MCP (plan "Tide list clean-up 2026-11",
/// Phase 2): two lessons of one sequence in one call, filing the same lesson
/// again, a group quick note on a plan recorded for fewer children, quick
/// notes dropping off the end-of-day list, and the quick note's stamp.
@Suite("MCP lesson loop gaps")
@MainActor
struct MCPLessonLoopGapTests {
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

    private func lesson(_ name: String, step: Int, in context: NSManagedObjectContext) -> CDLesson {
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

    /// The next five school days, from tomorrow.
    private func nextSchoolDays(in context: NSManagedObjectContext) -> [Date] {
        SchoolDayChecker.nextSchoolDays(from: AppCalendar.addingDays(1, to: Date()), count: 5, using: context)
    }

    private let practiceForOra: JSONValue = .array([.object([
        "student": .string("Ora"), "observation": .string("Wants more."), "follow_up": .string("practice")
    ])])

    private func oraWork(on lesson: CDLesson, in context: NSManagedObjectContext) throws -> CDWorkModel {
        try #require(context.safeFetch(CDFetchRequest(CDWorkModel.self)).first { $0.lessonID == lesson.id?.uuidString })
    }

    // MARK: - 1. Two lessons of one sequence in one call

    @Test("Recording the next lesson in the same call doesn't time the first one's practice by its plan")
    func secondLessonInTheCallIsNotAPlan() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let stamp = lesson("Stamp Game", step: 2, in: context)
        let ora = student("Ora", "Levi", in: context)
        let next = nextSchoolDays(in: context)
        PresentationFactory.makeDraft(lesson: stamp, students: [ora], context: context)
            .schedule(onDay: try #require(next.last))
        CoreDataTestHelpers.save(context)

        // Golden Beads listed first, on the same day: its practice is timed
        // while the Stamp Game plan is still waiting.
        _ = try await call("record_presentation", [
            "presentations": .array([
                .object([
                    "lesson": .string("Golden Beads"), "student_names": .array([.string("Ora")]),
                    "student_observations": practiceForOra
                ]),
                .object(["lesson": .string("Stamp Game"), "student_names": .array([.string("Ora")])])
            ])
        ], in: tools)
        let checkIns = WorkLogService.scheduledCheckIns(of: try oraWork(on: golden, in: context), in: context)
        #expect(checkIns.count == 1)
        #expect(checkIns.first?.date.map(AppCalendar.startOfDay) == next[2],
                "three school days after: the Stamp Game was given in the same call")
    }

    // MARK: - 2. Filing the same lesson again

    @Test("Filing the same lesson again keeps a check-in moved later, and its follow-up day")
    func filingAgainKeepsAMovedCheckIn() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        _ = student("Ora", "Levi", in: context)
        let filing: [String: JSONValue] = [
            "lesson": .string("Golden Beads"), "student_names": .array([.string("Ora")]),
            "student_observations": practiceForOra
        ]
        _ = try await call("record_presentation", filing, in: tools)
        let work = try oraWork(on: golden, in: context)
        let checkIn = try #require(WorkLogService.scheduledCheckIns(of: work, in: context).first)
        let later = AppCalendar.addingDays(14, to: try #require(checkIn.date))
        WorkCheckInService.move(checkIn, toDay: AppCalendar.startOfDay(later))
        CoreDataTestHelpers.save(context)

        _ = try await call("record_presentation", filing, in: tools)
        let scheduled = WorkLogService.scheduledCheckIns(of: work, in: context)
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.date.map(AppCalendar.startOfDay) == AppCalendar.startOfDay(later))
        let presentationID = try #require(work.presentationID.flatMap(UUID.init(uuidString:)))
        let row = PresentationFollowUpService.rows(for: presentationID, in: context).first
        #expect(row?.followUpReviewAt.map(AppCalendar.startOfDay) == AppCalendar.startOfDay(later),
                "her follow-up row keeps the day her check-in kept")
    }

    @Test("Filing the same lesson again adds no check-in after a done one")
    func filingAgainAddsNothingAfterADoneOne() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        _ = student("Ora", "Levi", in: context)
        let filing: [String: JSONValue] = [
            "lesson": .string("Golden Beads"), "student_names": .array([.string("Ora")]),
            "student_observations": practiceForOra
        ]
        _ = try await call("record_presentation", filing, in: tools)
        let work = try oraWork(on: golden, in: context)
        let first = try #require(WorkLogService.scheduledCheckIns(of: work, in: context).first)
        first.status = .completed
        CoreDataTestHelpers.save(context)

        _ = try await call("record_presentation", filing, in: tools)
        #expect(WorkLogService.scheduledCheckIns(of: work, in: context).isEmpty)
        #expect(WorkLogService.checkIns(of: work, in: context).count == 1)
    }

    // MARK: - 3. A group quick note on a plan given to fewer children

    @Test("A group quick note goes with the presentation recorded for fewer children")
    func groupQuickNoteGoesWithTheRecord() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let ora = student("Ora", "Levi", in: context)
        let etty = student("Etty", "Klein", in: context)
        let plan = PresentationFactory.makeDraft(lesson: golden, students: [ora, etty], context: context)
        plan.schedule(onDay: try day("2026-11-18"))
        let group = try #require(QuickNote.save(text: "Used the board", presentation: plan, context: context))
        let ettyID = try #require(etty.id)
        let ettys = try #require(QuickNote.save(
            text: "Ask Etty", presentation: plan, students: [ettyID], context: context
        ))

        _ = try await call("record_presentation", [
            "planned_presentation_id": .string(try #require(plan.id).uuidString),
            "student_names": .array([.string("Ora")]),
            "date": .string("2026-11-18")
        ], in: tools)
        let given = try #require(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).first { $0.isGiven })
        #expect(given != plan)
        #expect(group.lessonAssignment == given)
        #expect(ettys.lessonAssignment == plan, "a note about only Etty stays on her plan")
    }

    // MARK: - 4. Quick notes that dropped off the end-of-day list

    @Test("A quick note on a discarded lesson stays, and stays on the end-of-day list")
    func discardKeepsTheQuickNote() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let ora = student("Ora", "Levi", in: context)
        let plan = PresentationFactory.makeDraft(lesson: golden, students: [ora], context: context)
        plan.schedule(onDay: AppCalendar.startOfDay(Date()))
        let note = try #require(QuickNote.save(text: "Not today", presentation: plan, context: context))
        let noteID = try #require(note.id)

        let discarded = try await call("discard_presentation", [
            "presentation_id": .string(try #require(plan.id).uuidString), "confirm": .bool(true)
        ], in: tools)
        #expect(discarded.contains("1 quick note(s) still to fill in would stay"))
        let kept = try #require(context.object(CDNote.self, id: noteID))
        #expect(QuickNote.isWaiting(kept))
        #expect(kept.lessonID == golden.id?.uuidString)

        let output = try await call("schedule_for_range", ["view": .string("unrecorded")], in: tools)
        #expect(output.contains("[note id=\(noteID.uuidString)] \"Not today\" — Ora L (Golden Beads)"))
    }

    @Test("A quick note older than the days listed stays on the end-of-day list")
    func oldQuickNoteStaysListed() async throws {
        let (tools, context) = try makeTools()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let ora = student("Ora", "Levi", in: context)
        let given = PresentationFactory.makeDraft(lesson: golden, students: [ora], context: context)
        given.schedule(onDay: try day("2026-10-01"))
        given.markPresented(at: try day("2026-10-01"))
        let note = try #require(QuickNote.save(text: "Board", presentation: given, context: context))

        let output = try await call("schedule_for_range", ["view": .string("unrecorded")], in: tools)
        #expect(output.contains("Quick notes from before"))
        #expect(output.contains("[note id=\(try #require(note.id).uuidString)] \"Board\" — Ora L (Golden Beads), "
            + "written 2026-10-01"))
        #expect(output.contains("update_observation"))
    }

    // MARK: - 5. The stamp

    @Test("A quick note is stamped when it was written, on the day the lesson was given")
    func quickNoteStamp() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let golden = lesson("Golden Beads", step: 1, in: context)
        let ora = student("Ora", "Levi", in: context)
        let given = PresentationFactory.makeDraft(lesson: golden, students: [ora], context: context)
        given.markPresented(at: try day("2026-11-19"))
        let written = try #require(AppCalendar.shared.date(
            bySettingHour: 14, minute: 30, second: 0, of: try day("2026-11-19")
        ))

        let today = QuickNote.insert(body: "Board", presentation: given, students: [], context: context, now: written)
        #expect(today.createdAt == written)

        let nextDay = AppCalendar.addingDays(1, to: written)
        let late = QuickNote.insert(body: "Board", presentation: given, students: [], context: context, now: nextDay)
        #expect(late.createdAt == written, "the day it was given, at the time it was written")
    }
}
