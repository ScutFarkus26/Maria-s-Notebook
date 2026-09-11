import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// `student_tracks` reads a store that holds duplicate track definitions: a
/// migration that ran twice left twin rows under the same title, and some twins
/// kept none of the steps. The tool folds them by title the way the history tab
/// does, so a child gets one line per track she is actually on.
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

    /// A track with one step per lesson, in the order given.
    @discardableResult
    private func seedTrack(
        titled title: String, steps lessons: [CDLesson], in context: NSManagedObjectContext
    ) throws -> CDTrackEntity {
        let track = CDTrackEntity(context: context)
        track.title = title
        var rows: [CDTrackStepEntity] = []
        for (index, lesson) in lessons.enumerated() {
            let step = CDTrackStepEntity(context: context)
            step.track = track
            step.lessonTemplateID = try #require(lesson.id)
            step.orderIndex = Int64(index)
            rows.append(step)
        }
        track.steps = NSSet(array: rows)
        return track
    }

    @discardableResult
    private func enroll(
        _ student: CDStudent, on track: CDTrackEntity, isActive: Bool = true,
        attachRelationship: Bool = true, in context: NSManagedObjectContext
    ) throws -> CDStudentTrackEnrollmentEntity {
        let enrollment = CDStudentTrackEnrollmentEntity(context: context)
        enrollment.studentID = try #require(student.id).uuidString
        enrollment.trackID = try #require(track.id).uuidString
        enrollment.isActive = isActive
        enrollment.student = student
        if attachRelationship { enrollment.track = track }
        return enrollment
    }

    private func markProficient(
        _ student: CDStudent, on lesson: CDLesson, in context: NSManagedObjectContext
    ) throws {
        let row = CDLessonPresentation(context: context)
        row.studentID = try #require(student.id).uuidString
        row.lessonID = try #require(lesson.id).uuidString
        row.state = .proficient
        row.masteredAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    }

    private func lines(in output: String) -> [String] {
        output.split(separator: "\n").map(String.init).filter { $0.hasPrefix("- [track id=") }
    }

    // MARK: - Folding duplicate definitions

    /// Maya is enrolled on three rows that are really two tracks: the real
    /// "Commutative and Distributive" (3 steps, 2 mastered), its stepless twin,
    /// and a thinner twin of the same title (2 steps, 1 mastered).
    @Test("One line per track title, and the fuller definition wins")
    func foldsDuplicateTrackDefinitions() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Maya", lastName: "Schwartz", level: .upper
        )
        let commutative = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Commutative Law", area: "Math", sequence: "Laws"
        )
        let distributive = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Distributive Law", area: "Math", sequence: "Laws"
        )
        let associative = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Associative Law", area: "Math", sequence: "Laws"
        )

        let full = try seedTrack(
            titled: "Commutative and Distributive",
            steps: [commutative, distributive, associative], in: context
        )
        let shell = try seedTrack(titled: "Commutative and Distributive", steps: [], in: context)
        // Diacritics and case must not fork the fold either.
        let thin = try seedTrack(
            titled: "  commutative and distributive  ", steps: [commutative, distributive], in: context
        )

        try enroll(maya, on: full, in: context)
        try enroll(maya, on: shell, in: context)
        try enroll(maya, on: thin, in: context)
        try markProficient(maya, on: commutative, in: context)
        try markProficient(maya, on: distributive, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "student_tracks", in: tools).handler([
            "student_name": .string("Maya")
        ])

        let trackLines = lines(in: output)
        #expect(trackLines.count == 1, "three enrollments on one title print one line")
        let line = try #require(trackLines.first)
        let fullID = try #require(full.id).uuidString
        #expect(line.contains("2/3 steps mastered"), "the fuller definition wins the fold")
        #expect(line.contains("next: The Associative Law"))
        #expect(!output.contains("0/0"), "a stepless twin is not a track the child is on")
        #expect(line.contains("[track id=\(fullID)]"))
    }

    @Test("A stepless track is dropped even when it is the only enrollment")
    func steplessOnlyEnrollmentReadsAsNoTracks() async throws {
        let (tools, context) = try makeTools()
        let etty = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Etty", lastName: "Krinsky", level: .upper
        )
        let shell = try seedTrack(titled: "Geometry Lines", steps: [], in: context)
        try enroll(etty, on: shell, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "student_tracks", in: tools).handler([
            "student_name": .string("Etty")
        ])

        #expect(output == "Etty Krinsky's track enrollments have no tracks attached.")
        #expect(!output.contains("0/0"))
    }

    // MARK: - Enrollments whose relationship never arrived

    @Test("An enrollment with no track relationship is resolved by trackID")
    func fallsBackToTrackID() async throws {
        let (tools, context) = try makeTools()
        let sarah = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Sarah", lastName: "Gansburg", level: .upper
        )
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Parts of a Line", area: "Geometry", sequence: "Lines"
        )
        let track = try seedTrack(titled: "Geometry Lines", steps: [lesson], in: context)
        try enroll(sarah, on: track, attachRelationship: false, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let orphan = try #require(
            context.safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self)).first
        )
        #expect(orphan.track == nil, "the fixture must really be missing its relationship")

        let output = try await tool(named: "student_tracks", in: tools).handler([
            "student_name": .string("Sarah")
        ])

        let trackLines = lines(in: output)
        #expect(trackLines.count == 1)
        let line = try #require(trackLines.first)
        #expect(line.contains("Geometry Lines (0/1 steps mastered"))
    }

    // MARK: - What the fold must not change

    @Test("Two different titles still print two lines, and inactive is labelled")
    func keepsDistinctTracksApart() async throws {
        let (tools, context) = try makeTools()
        let chaya = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Chaya", lastName: "Marlow", level: .upper
        )
        let fractions = CoreDataTestHelpers.seedLesson(
            in: context, name: "Equivalent Fractions", area: "Math", sequence: "Fractions"
        )
        let lines2 = CoreDataTestHelpers.seedLesson(
            in: context, name: "Parts of a Line", area: "Geometry", sequence: "Lines"
        )
        let fractionsTrack = try seedTrack(titled: "Fractions", steps: [fractions], in: context)
        let geometryTrack = try seedTrack(titled: "Geometry Lines", steps: [lines2], in: context)
        try enroll(chaya, on: fractionsTrack, in: context)
        try enroll(chaya, on: geometryTrack, isActive: false, in: context)
        try markProficient(chaya, on: fractions, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "student_tracks", in: tools).handler([
            "student_name": .string("Chaya"),
            "include_inactive": .bool(true)
        ])

        let trackLines = lines(in: output)
        #expect(trackLines.count == 2)
        #expect(output.contains("Fractions (1/1 steps mastered; complete)"))
        #expect(output.contains("Geometry Lines (0/1 steps mastered; next: Parts of a Line; no longer active)"))
    }
}
