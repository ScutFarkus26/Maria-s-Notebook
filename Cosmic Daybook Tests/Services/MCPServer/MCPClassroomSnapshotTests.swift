import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `classroom_snapshot` hands Claude Desktop its first orientation, so its text
/// is pinned line for line over a fixture classroom: it was moved out of the
/// retired Ask AI code and must read exactly as it did.
@Suite("MCP classroom_snapshot")
@MainActor
struct MCPClassroomSnapshotTests {
    private func snapshot(in context: NSManagedObjectContext) async throws -> String {
        let tools = MCPNotebookTools.makeTools(context: { context })
        let tool = try #require(tools.first { $0.name == "classroom_snapshot" })
        return try await tool.handler([:])
    }

    private var today: String { DateFormatters.mediumDate.string(from: Date()) }

    private let footer = "Use notebook lookup tools for dates, observations, presentations, work, "
        + "attendance, and student-specific facts."

    @Test("An empty notebook has a date, a zero count and no Areas section")
    func emptyNotebook() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let text = try await snapshot(in: context)
        #expect(text == [
            "=== CLASSROOM SNAPSHOT ===",
            "Date: \(today)",
            "Enrolled student count: 0",
            "",
            footer
        ].joined(separator: "\n"))
    }

    @Test("A fixture classroom reads: today, enrolled count, sorted distinct areas")
    func fixtureClassroom() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Noa", lastName: "Katz",
            enrollmentStatus: .withdrawn, dateWithdrawn: Date(timeIntervalSinceNow: -86_400)
        )
        CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Decimal System")
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains", area: "Math", sequence: "Skip Counting")
        CoreDataTestHelpers.seedLesson(in: context, name: "Sentence Analysis", area: "Language", sequence: "Grammar")
        CoreDataTestHelpers.seedLesson(in: context, name: "Timeline of Life", area: "History", sequence: "Time")
        CoreDataTestHelpers.seedLesson(in: context, name: "No area yet", area: "", sequence: "")
        #expect(CoreDataTestHelpers.save(context))

        let text = try await snapshot(in: context)
        #expect(text == [
            "=== CLASSROOM SNAPSHOT ===",
            "Date: \(today)",
            "Enrolled student count: 2",
            "",
            "--- Areas ---",
            "History, Language, Math",
            "",
            footer
        ].joined(separator: "\n"))
    }

    @Test("The snapshot names no child")
    func namesNoChild() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        #expect(CoreDataTestHelpers.save(context))
        let text = try await snapshot(in: context)
        #expect(!text.contains("Maya"))
        #expect(!text.contains("Stern"))
    }
}
