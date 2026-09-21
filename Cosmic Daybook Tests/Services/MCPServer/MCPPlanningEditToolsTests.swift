import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Planning Edit Tools")
@MainActor
struct MCPPlanningEditToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        return (tools, context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func seedDivisionLesson(in context: NSManagedObjectContext) -> CDLesson {
        CoreDataTestHelpers.seedLesson(in: context, name: "Racks and Tubes", area: "Math", sequence: "Division")
    }

    private func presentations(in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
    }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext, student: CDStudent, lesson: CDLesson,
        plannedDate: Date?, status: YearPlanEntryStatus = .planned, track: String = "Math::Fractions"
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = plannedDate
        entry.sequenceGroupKey = track
        entry.statusRaw = status.rawValue
        return entry
    }

    // MARK: - discard_presentation

    @Test("discard_presentation without confirm reports lesson, day, roster and notes, and changes nothing")
    func discardReportsWithoutConfirm() async throws {
        let (tools, context) = try makeTools()
        let lesson = seedDivisionLesson(in: context)
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let planned = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ora, etty],
                scheduledFor: try CoreDataTestHelpers.day("2026-09-14"), context: context
        )
        let note = CDNote(context: context)
        note.body = "Bring the small bead frame too."
        note.lessonAssignment = planned
        #expect(CoreDataTestHelpers.save(context))
        let id = try #require(planned.id).uuidString

        let output = try await tool(named: "discard_presentation", in: tools).handler([
            "presentation_id": .string(id)
        ])
        #expect(output.hasPrefix("discard_presentation refused — nothing has been changed."))
        #expect(output.contains("[presentation id=\(id)] Racks and Tubes — scheduled 2026-09-14 — "
                                + "Ora Levi, Etty Klein"))
        #expect(output.contains("1 note(s) written on it would go with it."))
        #expect(presentations(in: context).count == 1)
        #expect(context.safeFetch(CDFetchRequest(CDNote.self)).count == 1)
    }

    @Test("discard_presentation with confirm deletes the plan, its notes, and returns a promoted entry to planned")
    func discardDeletesWithConfirm() async throws {
        let (tools, context) = try makeTools()
        let lesson = seedDivisionLesson(in: context)
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let planned = PresentationFactory.makeDraft(lesson: lesson, students: [ora], context: context)
        let kept = PresentationFactory.makeDraft(lesson: lesson, students: [ora], context: context)
        let note = CDNote(context: context)
        note.body = "Bring the small bead frame too."
        note.lessonAssignment = planned
        let entry = seedEntry(
            in: context, student: ora, lesson: lesson,
                plannedDate: try CoreDataTestHelpers.day("2026-09-14"), status: .promoted
        )
        entry.promotedAssignmentID = planned.id?.uuidString
        #expect(CoreDataTestHelpers.save(context))
        let id = try #require(planned.id).uuidString
        let keptID = try #require(kept.id)

        let output = try await tool(named: "discard_presentation", in: tools).handler([
            "presentation_id": .string(id), "confirm": .bool(true)
        ])
        #expect(output.hasPrefix("Discarded."))
        #expect(output.contains("not yet scheduled — Ora Levi"))
        #expect(output.contains("1 year-plan entry promoted into it would return to planned."))

        let remaining = presentations(in: context)
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == keptID)
        #expect(context.safeFetch(CDFetchRequest(CDNote.self)).isEmpty)
        #expect(entry.status == .planned)
        #expect(entry.promotedAssignmentID == nil)

        await #expect(throws: MCPToolError.self) {
            try await tool(named: "discard_presentation", in: tools).handler([
                "presentation_id": .string(id), "confirm": .bool(true)
            ])
        }
    }

    @Test("discard_presentation refuses a presentation already given")
    func discardRefusesGivenPresentation() async throws {
        let (tools, context) = try makeTools()
        let lesson = seedDivisionLesson(in: context)
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let given = PresentationFactory.makeDraft(lesson: lesson, students: [ora], context: context)
        given.markPresented(at: try CoreDataTestHelpers.day("2026-09-01"))
        #expect(CoreDataTestHelpers.save(context))
        let id = try #require(given.id).uuidString

        let refusal = await #expect(throws: MCPToolError.self) {
            try await tool(named: "discard_presentation", in: tools).handler([
                "presentation_id": .string(id), "confirm": .bool(true)
            ])
        }
        #expect(refusal?.message.contains("record_presentation") == true)
        #expect(presentations(in: context).count == 1)
    }

    // MARK: - update_presentation_roster

    @Test("update_presentation_roster adds and removes children in place")
    func rosterAddsAndRemoves() async throws {
        let (tools, context) = try makeTools()
        let lesson = seedDivisionLesson(in: context)
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        let planned = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ora, etty],
                scheduledFor: try CoreDataTestHelpers.day("2026-09-14"), context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        let id = try #require(planned.id)
        let before = planned.modifiedAt

        let output = try await tool(named: "update_presentation_roster", in: tools).handler([
            "presentation_id": .string(id.uuidString),
            "add_students": .array([.string("Maya"), .string("Ora")]),
            "remove_students": .array([.string("Etty")])
        ])
        #expect(output.hasPrefix("[presentation id=\(id.uuidString)] removed Etty Klein, added Maya Stern, "
                                 + "Ora Levi was already in the group."))
        #expect(output.contains("Now: Racks and Tubes — scheduled 2026-09-14 — Ora Levi, Maya Stern"))
        let expectedRoster: Set<UUID> = [try #require(ora.id), try #require(maya.id)]
        #expect(Set(planned.resolvedStudentIDs) == expectedRoster)
        #expect(planned.isScheduled)
        #expect(presentations(in: context).count == 1)
        #expect(planned.modifiedAt != before)

        await #expect(throws: MCPToolError.self) {
            try await tool(named: "update_presentation_roster", in: tools).handler([
                "presentation_id": .string(id.uuidString), "remove_students": .array([.string("Etty")])
            ])
        }
    }

    @Test("update_presentation_roster refuses to empty the group or touch a given presentation")
    func rosterRefusals() async throws {
        let (tools, context) = try makeTools()
        let lesson = seedDivisionLesson(in: context)
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        _ = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let planned = PresentationFactory.makeDraft(lesson: lesson, students: [ora], context: context)
        let given = PresentationFactory.makeDraft(lesson: lesson, students: [ora], context: context)
        given.markPresented(at: try CoreDataTestHelpers.day("2026-09-01"))
        #expect(CoreDataTestHelpers.save(context))
        let plannedID = try #require(planned.id).uuidString
        let givenID = try #require(given.id).uuidString

        let refusal = await #expect(throws: MCPToolError.self) {
            try await tool(named: "update_presentation_roster", in: tools).handler([
                "presentation_id": .string(plannedID), "remove_students": .array([.string("Ora")])
            ])
        }
        #expect(refusal?.message.contains("discard_presentation") == true)
        #expect(planned.studentIDs.count == 1)

        await #expect(throws: MCPToolError.self) {
            try await tool(named: "update_presentation_roster", in: tools).handler([
                "presentation_id": .string(givenID), "add_students": .array([.string("Etty")])
            ])
        }
        #expect(given.studentIDs.count == 1)
        await #expect(throws: MCPToolError.self) {
            try await tool(named: "update_presentation_roster", in: tools).handler([
                "presentation_id": .string(plannedID)
            ])
        }
    }

    // MARK: - clear_year_plan

    @Test("clear_year_plan scopes to a track and a date, previews without confirm, and skips with it")
    func clearYearPlanScopedPreviewThenApply() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let halves = CoreDataTestHelpers.seedLesson(
            in: context, name: "Halves", area: "Math", sequence: "Fractions"
        )
        let thirds = CoreDataTestHelpers.seedLesson(in: context, name: "Thirds", area: "Math", sequence: "Fractions")
        let beads = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Frame", area: "Math", sequence: "Operations"
        )
        let stale = seedEntry(in: context, student: ora, lesson: halves,
            plannedDate: try CoreDataTestHelpers.day("2026-03-02"))
        let ahead = seedEntry(in: context, student: ora, lesson: thirds,
            plannedDate: try CoreDataTestHelpers.day("2099-05-04"))
        let other = seedEntry(
            in: context, student: ora, lesson: beads,
                plannedDate: try CoreDataTestHelpers.day("2026-03-09"), track: "Math::Operations"
        )
        let promoted = seedEntry(
            in: context, student: ora, lesson: halves,
                plannedDate: try CoreDataTestHelpers.day("2026-03-01"), status: .promoted
        )
        #expect(CoreDataTestHelpers.save(context))

        let preview = try await tool(named: "clear_year_plan", in: tools).handler([
            "student_name": .string("Ora"), "track": .string("Fractions"), "before_date": .string("2026-09-01")
        ])
        #expect(preview.hasPrefix("clear_year_plan refused — nothing has been changed."))
        #expect(preview.contains("skip these 1 entry for Ora Levi in Fractions and targeted before 2026-09-01."))
        let staleID: String = try #require(stale.id).uuidString
        #expect(preview.contains("Math › Fractions (1):\n- [yearPlanEntry id=\(staleID)] Halves"))
        #expect(!preview.contains("Thirds") && !preview.contains("Bead Frame"))
        #expect(stale.status == .planned && ahead.status == .planned && other.status == .planned)

        let applied = try await tool(named: "clear_year_plan", in: tools).handler([
            "student_name": .string("Ora"), "track": .string("Math › Fractions"), "confirm": .bool(true)
        ])
        #expect(applied.hasPrefix("Skipped 2 year-plan entries for Ora Levi in Math › Fractions."))
        // The 2026-03-02 target predates this school year, so it reads as
        // carried over rather than behind pace; the 2099 one is neither.
        #expect(applied.contains("1 of 2 is carried over from last year."))
        #expect(!applied.contains("behind pace"))
        #expect(stale.status == .skipped && ahead.status == .skipped)
        #expect(other.status == .planned)
        #expect(promoted.status == .promoted)
        #expect(context.safeFetch(CDFetchRequest(CDYearPlanEntry.self)).count == 4)

        let nothing = try await tool(named: "clear_year_plan", in: tools).handler([
            "student_name": .string("Ora"), "track": .string("Fractions")
        ])
        #expect(nothing.hasPrefix("Ora Levi has no planned year-plan entries in Fractions."))
        #expect(nothing.contains("Planned tracks: Math › Operations."))
    }

    @Test("clear_year_plan with no scope previews the whole plan grouped by track")
    func clearYearPlanWholePlan() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let halves = CoreDataTestHelpers.seedLesson(
            in: context, name: "Halves", area: "Math", sequence: "Fractions"
        )
        let beads = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Frame", area: "Math", sequence: "Operations"
        )
        seedEntry(in: context, student: ora, lesson: halves, plannedDate: try CoreDataTestHelpers.day("2026-03-02"))
        seedEntry(in: context, student: ora, lesson: beads, plannedDate: nil, track: "Math::Operations")
        #expect(CoreDataTestHelpers.save(context))

        let preview = try await tool(named: "clear_year_plan", in: tools).handler([
            "student_name": .string("Ora")
        ])
        #expect(preview.contains("skip these 2 entries for Ora Levi.\n\n"))
        #expect(preview.contains("Math › Fractions (1):"))
        #expect(preview.contains("Math › Operations (1):"))

        // A date scope leaves undated entries alone.
        let dated = try await tool(named: "clear_year_plan", in: tools).handler([
            "student_name": .string("Ora"), "before_date": .string("2026-09-01"), "confirm": .bool(true)
        ])
        #expect(dated.hasPrefix("Skipped 1 year-plan entry for Ora Levi targeted before 2026-09-01."))
        let entries = context.safeFetch(CDFetchRequest(CDYearPlanEntry.self))
        #expect(entries.filter(\.isPlanned).count == 1)
        #expect(entries.filter { $0.status == .skipped }.count == 1)
    }
}
