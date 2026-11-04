import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `student_tracks` reads where a child stands on each lesson sequence from
/// her presentation rows (`SequenceStandingLoader`, 2026-11-03), not from
/// track enrollments: one line per sequence she has started.
@Suite("MCP Student Tracks Tool")
@MainActor
struct MCPStudentTracksToolTests {

    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    // MARK: - Seeding

    /// Lessons `names` in one sequence, numbered in the order given.
    private func seedSequence(
        _ names: [String], area: String, sequence: String, in context: NSManagedObjectContext
    ) -> [CDLesson] {
        names.enumerated().map { index, name in
            let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
            lesson.orderInSequence = Int64(index)
            return lesson
        }
    }

    private func give(
        _ lesson: CDLesson, to student: CDStudent, marked: Bool = false, in context: NSManagedObjectContext
    ) throws {
        let row = CDLessonPresentation(context: context)
        row.studentID = try #require(student.id).uuidString
        row.lessonID = try #require(lesson.id).uuidString
        row.presentedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        row.state = marked ? .proficient : .presented
        row.masteredAt = marked ? Date(timeIntervalSinceReferenceDate: 800_000_000) : nil
    }

    private func lines(in output: String) -> [String] {
        output.split(separator: "\n").map(String.init).filter { $0.hasPrefix("- [sequence: ") }
    }

    // MARK: - Standing from the rows

    @Test("One line per sequence she has started, with mastery count and the lesson she is up to")
    func linesComeFromHerRows() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Maya", lastName: "Schwartz", level: .upper
        )
        let laws = seedSequence(
            ["The Commutative Law", "The Distributive Law", "The Associative Law"],
            area: "Math", sequence: "Laws", in: context
        )
        let lines2 = seedSequence(
            ["Parts of a Line", "Kinds of Lines"], area: "Geometry", sequence: "Lines", in: context
        )
        try give(laws[0], to: maya, marked: true, in: context)
        try give(laws[1], to: maya, marked: true, in: context)
        try give(lines2[0], to: maya, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "student_tracks", in: tools).handler([
            "student_name": .string("Maya")
        ])

        #expect(output.hasPrefix("Maya Schwartz's sequences:"))
        #expect(lines(in: output) == [
            "- [sequence: Geometry — Lines] 0/2 lessons mastered; next: Kinds of Lines",
            "- [sequence: Math — Laws] 2/3 lessons mastered; next: The Associative Law"
        ])
        #expect(!output.contains("track id="))
    }

    @Test("A child with no presentation rows has not started any sequence")
    func noRowsNoSequences() async throws {
        let (tools, context) = try makeTools()
        _ = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Krinsky", level: .upper)
        _ = seedSequence(["Parts of a Line"], area: "Geometry", sequence: "Lines", in: context)
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "student_tracks", in: tools).handler([
            "student_name": .string("Etty")
        ])

        #expect(output == "Etty Krinsky has not started any lesson sequences.")
    }

    @Test("A finished sequence is left out by default and labelled complete with include_inactive")
    func finishedOnlyOnRequest() async throws {
        let (tools, context) = try makeTools()
        let chaya = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Chaya", lastName: "Marlow", level: .upper
        )
        let fractions = seedSequence(["Equivalent Fractions"], area: "Math", sequence: "Fractions", in: context)
        let lines2 = seedSequence(["Parts of a Line"], area: "Geometry", sequence: "Lines", in: context)
        try give(fractions[0], to: chaya, marked: true, in: context)
        try give(lines2[0], to: chaya, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let byDefault = try await tool(named: "student_tracks", in: tools).handler([
            "student_name": .string("Chaya")
        ])
        #expect(lines(in: byDefault) == ["- [sequence: Geometry — Lines] 0/1 lessons mastered"])

        let withFinished = try await tool(named: "student_tracks", in: tools).handler([
            "student_name": .string("Chaya"),
            "include_inactive": .bool(true)
        ])
        #expect(lines(in: withFinished) == [
            "- [sequence: Geometry — Lines] 0/1 lessons mastered",
            "- [sequence: Math — Fractions] 1/1 lessons mastered; complete"
        ])
    }

    @Test("A classmate's rows never count toward her standing")
    func classmatesRowsDoNotCount() async throws {
        let (tools, context) = try makeTools()
        let sarah = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Sarah", lastName: "Gansburg", level: .upper
        )
        let other = CoreDataTestHelpers.seedStudent(in: context, firstName: "Other", lastName: "Child", level: .upper)
        let lines2 = seedSequence(
            ["Parts of a Line", "Kinds of Lines"], area: "Geometry", sequence: "Lines", in: context
        )
        try give(lines2[0], to: sarah, in: context)
        try give(lines2[0], to: other, marked: true, in: context)
        try give(lines2[1], to: other, marked: true, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "student_tracks", in: tools).handler([
            "student_name": .string("Sarah")
        ])

        #expect(lines(in: output) == ["- [sequence: Geometry — Lines] 0/2 lessons mastered; next: Kinds of Lines"])
    }
}
