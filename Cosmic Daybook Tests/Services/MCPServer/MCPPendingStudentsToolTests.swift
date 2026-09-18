import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Students Pending Tool")
@MainActor
struct MCPPendingStudentsToolTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    /// A day relative to today, clamped forward to the first day of this
    /// school year. A target before that is *carried over*, not behind pace,
    /// and the expectations below read the behind-pace wording — the clamp is
    /// what keeps the suite stable across a school-year boundary. The assertions
    /// format their expected dates through this same helper, so both sides move
    /// together.
    private func daysFromToday(_ days: Int) -> Date {
        let seed = AppCalendar.shared.date(
            byAdding: .day, value: days, to: AppCalendar.startOfDay(Date())
        )!
        return max(seed, YearPlanStaleness.currentYearStart())
    }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext, student: CDStudent, lesson: CDLesson,
        plannedDate: Date?, status: YearPlanEntryStatus = .planned
    ) throws -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(student.id).uuidString
        entry.lessonID = try #require(lesson.id).uuidString
        entry.plannedDate = plannedDate
        entry.sequenceGroupKey = "Math::Laws"
        entry.statusRaw = status.rawValue
        return entry
    }

    /// Seven children and the Distributive Law:
    /// - Ora: planned, target passed → behind pace, nothing on the calendar
    /// - Etty: planned, target ahead, and a scheduled presentation with Dalia
    /// - Dalia: no entry, but on that scheduled presentation
    /// - Maya: promoted entry linked to a draft (undated) presentation
    /// - Noa: planned entry the record already answers (given last spring)
    /// - Tova: promoted entry whose presentation has since been given
    /// - Sarah: nothing at all
    /// - Rivka: withdrawn, with a planned entry that must not show
    private struct Classroom {
        let distributive: CDLesson
        let scheduled: CDLessonAssignment
    }

    private func seedClassroom(in context: NSManagedObjectContext) throws -> Classroom {
        let distributive = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Distributive Law of Multiplication", area: "Math", sequence: "Laws"
        )
        let other = CoreDataTestHelpers.seedLesson(in: context, name: "Bells", area: "Music", sequence: "Tone Bars")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let dalia = CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Roth")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let noa = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Katz")
        let tova = CoreDataTestHelpers.seedStudent(in: context, firstName: "Tova", lastName: "Brand")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Adler")
        let rivka = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.save(context)

        try seedEntry(in: context, student: ora, lesson: distributive, plannedDate: daysFromToday(-5))
        try seedEntry(in: context, student: etty, lesson: distributive, plannedDate: daysFromToday(9))
        try seedEntry(in: context, student: rivka, lesson: distributive, plannedDate: daysFromToday(2))
        try seedEntry(in: context, student: ora, lesson: other, plannedDate: daysFromToday(1))

        let scheduled = PresentationFactory.makeScheduled(
            lesson: distributive, students: [etty, dalia], scheduledFor: daysFromToday(12), context: context
        )
        let draft = PresentationFactory.makeDraft(lesson: distributive, students: [maya], context: context)
        let promoted = try seedEntry(
            in: context, student: maya, lesson: distributive, plannedDate: daysFromToday(3), status: .promoted
        )
        promoted.promotedAssignmentID = draft.id?.uuidString

        try seedEntry(in: context, student: noa, lesson: distributive, plannedDate: daysFromToday(-30))
        let given = PresentationFactory.makeDraft(lesson: distributive, students: [noa], context: context)
        given.markPresented(at: try day("2026-04-02"))
        let record = CDLessonPresentation(context: context)
        record.studentID = try #require(noa.id).uuidString
        record.lessonID = try #require(distributive.id).uuidString
        record.presentedAt = try day("2026-04-02")

        // Promoted onto the calendar, then given: the entry still reads
        // promoted, but the presentation behind it is history now.
        let tovaGiven = PresentationFactory.makeDraft(lesson: distributive, students: [tova], context: context)
        tovaGiven.markPresented(at: try day("2026-08-31"))
        let tovaEntry = try seedEntry(
            in: context, student: tova, lesson: distributive, plannedDate: try day("2026-08-31"), status: .promoted
        )
        tovaEntry.promotedAssignmentID = tovaGiven.id?.uuidString
        #expect(CoreDataTestHelpers.save(context))
        return Classroom(distributive: distributive, scheduled: scheduled)
    }

    @Test("students_pending lists every enrolled child with the lesson ahead of her, soonest target first")
    func pendingListsTargetsPaceAndCalendar() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let scheduledID = try #require(classroom.scheduled.id).uuidString

        let output = try await tool(named: "students_pending", in: tools).handler([
            "lesson": .string("distributive law")
        ])
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines[0].hasSuffix(
            "The Distributive Law of Multiplication — Math › Laws — pending for 4 of 7 enrolled child(ren):"
        ))

        // Order: Ora (target passed), Maya (+3), Etty (+9), Dalia (no target; her presentation is +12).
        let ora = try #require(lines.first { $0.contains("] Ora Levi —") })
        let oraTarget = MCPNotebookTools.dayString(daysFromToday(-5))
        #expect(ora.contains("target \(oraTarget) (behind pace) — not on the calendar"))
        let maya = try #require(lines.first { $0.contains("] Maya Soto —") })
        let mayaTarget = MCPNotebookTools.dayString(daysFromToday(3))
        #expect(maya.contains("target \(mayaTarget) — in the planning list, undated [presentation id="))
        #expect(!maya.contains("behind pace"))
        let etty = try #require(lines.first { $0.contains("] Etty Klein —") })
        let sitting = MCPNotebookTools.dayString(daysFromToday(12))
        let ettyTarget = MCPNotebookTools.dayString(daysFromToday(9))
        #expect(etty.contains("target \(ettyTarget) — scheduled \(sitting) in the morning "))
        #expect(etty.contains("with Dalia Roth [presentation id=\(scheduledID)]"))
        let dalia = try #require(lines.first { $0.contains("] Dalia Roth —") })
        #expect(dalia.contains("no year-plan entry — scheduled \(sitting) in the morning "))
        #expect(dalia.contains("with Etty Klein"))

        let order = ["Ora Levi", "Maya Soto", "Etty Klein", "Dalia Roth"].map { name in
            lines.firstIndex { $0.contains("] \(name) —") }!
        }
        #expect(order == order.sorted())

        #expect(output.contains("Already given (2): Tova Brand, Noa Katz"))
        #expect(!output.contains("presentation is gone"))
        #expect(output.contains("No plan for it (1): Sarah Adler"))
        #expect(!output.contains("Rivka"))
    }

    @Test("students_pending takes a lesson id, reports an empty plan, and refuses an unknown lesson")
    func pendingByIDEmptyAndRefusal() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let pending = try tool(named: "students_pending", in: tools)

        let byID = try await pending.handler(["lesson": .string(try #require(classroom.distributive.id).uuidString)])
        #expect(byID.contains("pending for 4 of 7"))

        let bells = try await pending.handler(["lesson": .string("Bells")])
        #expect(bells.contains("Bells — Music › Tone Bars — pending for 1 of 7 enrolled child(ren):"))
        #expect(bells.contains("Ora Levi — target"))
        #expect(bells.contains("No plan for it (6):"))

        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await pending.handler(["lesson": .string("Astronomy")])
        }
        #expect(refusal?.message.contains("find_lessons") == true)
    }
}
