import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, Part 2 #78 and #90: AI-plan Apply saves and can't be
// pressed twice; suggestions find their lesson by area and sequence first.

/// No model behind it: these tests never ask the planner for suggestions.
private struct NoModelClient: MCPClientProtocol {
    struct Unavailable: Error {}
    func generateText(prompt: String, temperature: Double) async throws -> String { throw Unavailable() }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { throw Unavailable() }
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?
    ) async throws -> String { throw Unavailable() }
}

@Suite("AI plan Apply (Fix1010J2b)")
@MainActor
struct AIPlanApplyFix1010J2bTests {
    @Test("Apply saves the drafts, then hides, so a second press adds nothing")
    func applySavesOnceAndHides() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Cohen")
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game", area: "Mathematics", sequence: "Decimal System"
        )
        try context.save()
        let studentID = try #require(student.id)
        let lessonID = try #require(lesson.id)

        let viewModel = LessonPlanningViewModel(mode: .singleStudent(studentID))
        viewModel.configure(context: context, mcpClient: NoModelClient(), saveCoordinator: SaveCoordinator())
        var recommendation = LessonRecommendation(
            lessonID: lessonID, lessonName: "Stamp Game", area: "Mathematics", sequence: "Decimal System",
            studentIDs: [studentID], studentNames: ["Maya Cohen"], reasoning: "Next in sequence", priority: 1
        )
        recommendation.decision = .accepted
        viewModel.recommendations = [recommendation]
        #expect(viewModel.canApplyPlan)

        viewModel.applyPlan()

        #expect(viewModel.errorMessage == nil)
        #expect(!context.hasChanges, "The drafts were saved, not left waiting in memory")
        #expect(!viewModel.canApplyPlan, "Apply is gone once its lessons are in the plan")

        viewModel.applyPlan()
        let drafts = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        #expect(drafts.count == 1)
        #expect(drafts.first?.lessonID == lessonID.uuidString)
    }
}

@Suite("AI plan lesson matching (Fix1010J2b)")
struct AIPlanLessonMatchingFix1010J2bTests {
    private let mathIntro = LessonData(
        id: UUID(), name: "Introduction", area: "Mathematics", sequence: "Decimal System"
    )
    private let geographyIntro = LessonData(id: UUID(), name: "Introduction", area: "Geography", sequence: "Maps")
    private let geographyGlobes = LessonData(
        id: UUID(), name: "Introduction to Globes", area: "Geography", sequence: "Globes"
    )

    @Test("Of two lessons with the same name, the one in the suggested area wins")
    func sameNamePrefersArea() {
        let id = LessonPlanningService.resolveLessonID(
            named: "Introduction", area: "Geography", sequence: "Maps", in: [mathIntro, geographyIntro]
        )
        #expect(id == geographyIntro.id)
    }

    @Test("Name matching ignores case and accents; an unknown area falls back to curriculum order")
    func unknownAreaFallsBack() {
        let id = LessonPlanningService.resolveLessonID(
            named: "INTRODUCTIÓN", area: "Art", sequence: "", in: [mathIntro, geographyIntro]
        )
        #expect(id == mathIntro.id)
    }

    @Test("A partial name is looked for in the suggested area first")
    func partialNamePrefersArea() {
        let mathGlobes = LessonData(id: UUID(), name: "Globes of Numbers", area: "Mathematics", sequence: "Fun")
        let id = LessonPlanningService.resolveLessonID(
            named: "globes", area: "Geography", sequence: "Globes", in: [mathGlobes, geographyGlobes]
        )
        #expect(id == geographyGlobes.id)
    }

    @Test("A name that matches nothing finds nothing")
    func noMatch() {
        #expect(LessonPlanningService.resolveLessonID(
            named: "Pink Tower", area: "Sensorial", sequence: "", in: [mathIntro, geographyIntro]
        ) == nil)
    }
}
