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
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?
    ) async throws -> String { "" }
}

/// Pins what one Insights analysis materialises for a student. Her notes
/// and work completions are fetched by her id, her practice check-ins by her
/// work's ids (read as plain values). The snapshot's counts must not change.
@Suite("Student Analysis Service scope")
@MainActor
struct StudentAnalysisServiceScopeTests {

    private struct Seeded {
        let stack: CoreDataStack
        let student: CDStudent
    }

    /// One student with two notes, one practice check-in and one completion
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
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame", studentID: studentID)
        // Minutes only, so no note: her two notes stay the only ones.
        PracticeCheckIns.record(PracticeRecord(date: Date(), minutes: 15), on: work, in: context)
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
        // The rating is a word on the check-in's note now, not a number: 0 is
        // the snapshot's "no average", which Insights doesn't show.
        #expect(snapshot.averagePracticeQuality == 0)
        #expect(snapshot.keyStrengths == ["focus"])
    }

    @Test("One analysis materialises her rows and nobody else's")
    func analysisMaterialisesOnlyTheStudentsRows() async throws {
        let seeded = try seed(others: 12)
        let context = seeded.stack.viewContext
        let before = context.registeredObjects.count
        let service = StudentAnalysisService(modelContext: context, mcpClient: CannedAnalysisClient())
        _ = try await service.analyzeStudent(seeded.student, lookbackDays: 30)
        let registered = context.registeredObjects.count - before
        // Her two notes, her completion, her practice check-in and the new
        // snapshot: 5. Her work ids are read as values, not rows.
        #expect(registered <= 5, "registered \(registered) objects for one student")
    }
}
