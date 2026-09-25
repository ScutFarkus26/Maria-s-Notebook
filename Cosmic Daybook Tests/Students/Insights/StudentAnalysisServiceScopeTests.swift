import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Answers every analysis with the same well-formed JSON, so the test
/// exercises the Core Data reads and the snapshot, not a model.
private struct CannedAnalysisClient: MCPClientProtocol {
    static let json = """
    {"overallProgress": "Steady", "keyStrengths": ["focus"], "areasForGrowth": ["handwriting"],
     "developmentalMilestones": [], "observedPatterns": [], "behavioralTrends": [],
     "socialEmotionalInsights": [], "recommendedNextLessons": [], "suggestedPracticeFocus": [],
     "interventionSuggestions": []}
    """
    func generateText(prompt: String, temperature: Double) async throws -> String { "" }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { Self.json }
    // swiftlint:disable:next function_parameter_count
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, model: String?, timeout: TimeInterval?
    ) async throws -> String { "" }
    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, model: String?, timeout: TimeInterval?,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String { "" }
}

/// Pins what one Insights analysis materialises for a student. Her notes
/// and work completions are fetched by her id; practice sessions carry their
/// roster as a Transformable blob, so the lookback window's sessions for the
/// whole class are read and filtered in memory, as the progress tab's
/// projects are. The snapshot's counts must not change.
@Suite("Student Analysis Service scope")
@MainActor
struct StudentAnalysisServiceScopeTests {

    private struct Seeded {
        let stack: CoreDataStack
        let student: CDStudent
    }

    /// One student with two notes, one practice session and one completion
    /// inside the 30-day window plus a note outside it, next to `others`
    /// classmates carrying the same shape.
    private func seed(others: Int) throws -> Seeded {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let studentID = try #require(student.id)
        seedActivity(for: studentID, in: context)
        let old = CoreDataTestHelpers.seedNote(in: context, body: "Last spring")
        old.scope = .student(studentID)
        old.createdAt = AppCalendar.shared.date(byAdding: .day, value: -90, to: Date())
        for index in 0..<others {
            let other = CoreDataTestHelpers.seedStudent(in: context, firstName: "Other", lastName: "\(index)")
            seedActivity(for: try #require(other.id), in: context)
        }
        try context.save()
        context.reset()
        return Seeded(stack: stack, student: try #require(context.object(CDStudent.self, id: studentID)))
    }

    private func seedActivity(for studentID: UUID, in context: NSManagedObjectContext) {
        for body in ["Chose the bead frame", "Read aloud to a friend"] {
            CoreDataTestHelpers.seedNote(in: context, body: body).scope = .student(studentID)
        }
        let session = CDPracticeSession(context: context)
        session.studentIDsArray = [studentID.uuidString]
        session.practiceQuality = 4
        let completion = CDWorkCompletionRecord(context: context)
        completion.studentID = studentID.uuidString
    }

    @Test("The snapshot counts her recent notes, sessions and completions, not the classroom's")
    func snapshotCountsOnlyTheStudentsRecentActivity() async throws {
        let seeded = try seed(others: 12)
        let service = StudentAnalysisService(
            modelContext: seeded.stack.viewContext, mcpClient: CannedAnalysisClient()
        )
        let snapshot = try await service.analyzeStudent(seeded.student, lookbackDays: 30)
        #expect(snapshot.totalNotesAnalyzed == 2)
        #expect(snapshot.practiceSessionsAnalyzed == 1)
        #expect(snapshot.workCompletionsAnalyzed == 1)
        #expect(snapshot.averagePracticeQuality == 4)
        #expect(snapshot.keyStrengths == ["focus"])
    }

    @Test("One analysis materialises her rows plus the window's practice sessions")
    func analysisMaterialisesOnlyTheStudentsRows() async throws {
        let seeded = try seed(others: 12)
        let context = seeded.stack.viewContext
        let before = context.registeredObjects.count
        let service = StudentAnalysisService(modelContext: context, mcpClient: CannedAnalysisClient())
        _ = try await service.analyzeStudent(seeded.student, lookbackDays: 30)
        let registered = context.registeredObjects.count - before
        // Her two notes, her completion, the new snapshot, and the window's 13
        // practice sessions (hers and the 12 classmates'): 17. The roster on
        // a practice session is a Transformable blob, so the store cannot
        // narrow that read to her.
        #expect(registered <= 17, "registered \(registered) objects for one student")
    }
}
