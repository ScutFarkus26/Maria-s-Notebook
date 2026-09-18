import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What the guide's MCP client is told about a target from last school year.
/// "Behind pace" is an instruction to catch up; "carried over" is an invitation
/// to re-date or skip. Over the wire the difference is the whole point, so the
/// wording is pinned here.
///
/// Every date is seeded relative to `YearPlanStaleness.currentYearStart()`
/// rather than by moving the school-year start in UserDefaults: these tests
/// share a process with the rest of the suite, and a mutated default would
/// leak into it.
@Suite("MCP Year Plan — Carried Over")
@MainActor
struct MCPYearPlanCarryOverToolTests {

    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private var yearStart: Date { YearPlanStaleness.currentYearStart() }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext,
        student: CDStudent,
        lesson: CDLesson,
        plannedDate: Date?,
        status: YearPlanEntryStatus = .planned
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = plannedDate
        entry.sequenceGroupKey = "Math::Fractions"
        entry.statusRaw = status.rawValue
        return entry
    }

    @Test("year_plan calls last year's target carried over, never behind pace")
    func yearPlanNamesCarriedOverEntries() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Halves", area: "Math", sequence: "Fractions"
        )
        seedEntry(
            in: context, student: ora, lesson: lesson,
            plannedDate: AppCalendar.addingDays(-10, to: yearStart)
        )
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "year_plan", in: tools).handler([
            "student_name": .string("Ora")
        ])

        #expect(output.contains("carried over from"))
        #expect(!output.contains("behind pace"))
        // The closing summary says how many, and what clears them.
        let start = MCPNotebookTools.dayString(yearStart)
        #expect(output.contains("1 of them is carried over from last year (targets before \(start))"))
        #expect(output.contains("clear_year_plan"))
    }

    @Test("a target inside this school year is still reported behind pace")
    func thisYearsLateTargetIsStillBehind() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Thirds", area: "Math", sequence: "Fractions"
        )
        // The day after the year started, which is in the past for most of the
        // year; on the first two mornings of school nothing can be behind yet.
        let target = AppCalendar.addingDays(1, to: yearStart)
        guard target < AppCalendar.startOfDay(Date()) else { return }
        seedEntry(in: context, student: ora, lesson: lesson, plannedDate: target)
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "year_plan", in: tools).handler([
            "student_name": .string("Ora")
        ])

        #expect(output.contains("behind pace"))
        #expect(!output.contains("carried over from"))
    }

    @Test("students_pending marks a carried-over child as carried over, not behind pace")
    func pendingNamesCarriedOver() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Checkerboard", area: "Math", sequence: "Operations"
        )
        seedEntry(
            in: context, student: ora, lesson: lesson,
            plannedDate: AppCalendar.addingDays(-20, to: yearStart)
        )
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "students_pending", in: tools).handler([
            "lesson": .string("The Checkerboard")
        ])

        #expect(output.contains("(carried over)"))
        #expect(!output.contains("(behind pace)"))
    }

    @Test("clear_year_plan's receipt counts carried-over entries beside the behind-pace ones")
    func clearReceiptCountsCarriedOver() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Quarters", area: "Math", sequence: "Fractions"
        )
        seedEntry(
            in: context, student: ora, lesson: lesson,
            plannedDate: AppCalendar.addingDays(-30, to: yearStart)
        )
        seedEntry(
            in: context, student: ora, lesson: lesson,
            plannedDate: AppCalendar.addingDays(-40, to: yearStart)
        )
        CoreDataTestHelpers.save(context)

        let preview = try await tool(named: "clear_year_plan", in: tools).handler([
            "student_name": .string("Ora")
        ])

        #expect(preview.contains("2 of 2 are carried over from last year."))
        #expect(!preview.contains("behind pace"))
    }
}
