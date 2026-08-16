// swiftlint:disable file_length
import Foundation

// MARK: - Planning Depth

/// Controls how many AI pipeline steps to run and the corresponding cost/detail tradeoff.
enum PlanningDepth: String, Codable, CaseIterable, Identifiable {
    /// Steps 1-2 only: local evidence assembly + gap analysis.
    case quick
    /// Steps 1-3: adds plan synthesis with day scheduling.
    case standard
    /// Steps 1-4: adds whole-class week optimization.
    case deep
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .quick: return "Quick"
        case .standard: return "Standard"
        case .deep: return "Deep"
        }
    }
    
    var description: String {
        switch self {
        case .quick: return "Fast suggestions from curriculum and guide records"
        case .standard: return "Scheduled plan with grouping suggestions"
        case .deep: return "Full weekly optimization across all students"
        }
    }
}

// MARK: - Planning Mode

/// Determines what the planning session is focused on.
enum PlanningMode: Equatable {
    case singleStudent(UUID)
    case wholeClass
    case quickSuggest([UUID])
}

// MARK: - Pipeline Step

/// Tracks which step of the AI pipeline is currently executing.
enum PipelineStep: String, Codable {
    case idle
    case gatheringData
    case gatheringEvidence
    case generatingPlan
    case presentingPlan
    case awaitingInput
    case respondingToQuestion
    case creatingAssignments
    case complete
    
    var displayLabel: String {
        switch self {
        case .idle: return "Ready"
        case .gatheringData: return "Gathering data..."
        case .gatheringEvidence: return "Gathering evidence..."
        case .generatingPlan: return "Generating plan..."
        case .presentingPlan: return "Plan ready"
        case .awaitingInput: return "Awaiting input"
        case .respondingToQuestion: return "Thinking..."
        case .creatingAssignments: return "Creating assignments..."
        case .complete: return "Complete"
        }
    }
}

// MARK: - Planning Session

/// In-memory state for a planning conversation session.
struct PlanningSession: Identifiable {
    let id: UUID
    let mode: PlanningMode
    let depth: PlanningDepth
    let startedAt: Date
    var messages: [PlanningMessage] = []
    var recommendations: [LessonRecommendation] = []
    var weekPlan: WeekPlan?
    var readinessProfiles: [StudentReadinessProfile] = []
    var tokensUsed: Int = 0
    
    init(mode: PlanningMode, depth: PlanningDepth) {
        self.id = UUID()
        self.mode = mode
        self.depth = depth
        self.startedAt = Date()
    }
}

// MARK: - Planning Message

/// A single message in the planning conversation.
struct PlanningMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    var recommendationIDs: [UUID]
    
    enum MessageRole: String, Codable {
        case teacher
        case assistant
        case system
    }
    
    init(role: MessageRole, content: String, recommendationIDs: [UUID] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.recommendationIDs = recommendationIDs
    }
}

// MARK: - CDLesson Recommendation

/// How much direct, locally recorded evidence supports a planning candidate.
/// This describes evidence availability, not whether a child is ready.
enum EvidenceAvailability: String, Codable, CaseIterable {
    case strong
    case some
    case insufficient

    var displayLabel: String {
        switch self {
        case .strong: return "Strong evidence"
        case .some: return "Some evidence"
        case .insufficient: return "Insufficient evidence"
        }
    }

    /// Combines evidence for a group conservatively: the least-supported child
    /// determines the label shown on the shared recommendation.
    static func combined(_ values: [EvidenceAvailability]) -> EvidenceAvailability {
        guard !values.isEmpty else { return .insufficient }
        if values.contains(.insufficient) { return .insufficient }
        if values.contains(.some) { return .some }
        return .strong
    }
}

/// A lesson candidate assembled from local records and optionally arranged by AI.
struct LessonRecommendation: Identifiable, Codable {
    let id: UUID
    let lessonID: UUID
    let lessonName: String
    let area: String
    let sequence: String
    let studentIDs: [UUID]
    let studentNames: [String]
    let reasoning: String
    /// Legacy model confidence retained for feedback-record compatibility. It is
    /// intentionally not presented as evidence or readiness in the UI.
    let confidence: Double
    let evidenceAvailability: EvidenceAvailability
    let priority: Int
    let suggestedDay: String?
    var decision: TeacherDecision?
    
    init(
        lessonID: UUID,
        lessonName: String,
        area: String,
        sequence: String,
        studentIDs: [UUID],
        studentNames: [String],
        reasoning: String,
        confidence: Double = 0,
        evidenceAvailability: EvidenceAvailability = .insufficient,
        priority: Int,
        suggestedDay: String? = nil
    ) {
        self.id = UUID()
        self.lessonID = lessonID
        self.lessonName = lessonName
        self.area = area
        self.sequence = sequence
        self.studentIDs = studentIDs
        self.studentNames = studentNames
        self.reasoning = reasoning
        self.confidence = confidence
        self.evidenceAvailability = evidenceAvailability
        self.priority = priority
        self.suggestedDay = suggestedDay
    }
}

// MARK: - Grouping Suggestion

/// Suggests grouping students together for a shared lesson presentation.
struct GroupingSuggestion: Identifiable, Codable {
    let id: UUID
    let lessonID: UUID
    let lessonName: String
    let studentIDs: [UUID]
    let studentNames: [String]
    let rationale: String
    
    init(lessonID: UUID, lessonName: String, studentIDs: [UUID], studentNames: [String], rationale: String) {
        self.id = UUID()
        self.lessonID = lessonID
        self.lessonName = lessonName
        self.studentIDs = studentIDs
        self.studentNames = studentNames
        self.rationale = rationale
    }
}

// MARK: - Week Plan

/// A complete weekly lesson plan.
struct WeekPlan: Codable {
    let weekStartDate: Date
    var days: [DayPlanEntry]
    var groupings: [GroupingSuggestion]
    var summary: String
    
    struct DayPlanEntry: Identifiable, Codable {
        let id: UUID
        let dayName: String
        let date: Date
        var recommendations: [LessonRecommendation]
        
        init(dayName: String, date: Date, recommendations: [LessonRecommendation] = []) {
            self.id = UUID()
            self.dayName = dayName
            self.date = date
            self.recommendations = recommendations
        }
    }
}

// MARK: - CDStudent Planning Evidence Profile

/// Locally-computed factual profile for planning. It intentionally excludes
/// practice ratings, behavior labels, and inferred social-emotional judgments.
struct StudentReadinessProfile: Identifiable, Codable {
    let id: UUID
    let studentID: UUID
    let studentName: String
    let level: String
    var areaReadiness: [AreaReadiness]
    let daysSinceLastPresentation: Int?
    let activeWorkCount: Int
    
    init(
        studentID: UUID,
        studentName: String,
        level: String,
        areaReadiness: [AreaReadiness],
        daysSinceLastPresentation: Int?,
        activeWorkCount: Int
    ) {
        self.id = UUID()
        self.studentID = studentID
        self.studentName = studentName
        self.level = level
        self.areaReadiness = areaReadiness
        self.daysSinceLastPresentation = daysSinceLastPresentation
        self.activeWorkCount = activeWorkCount
    }
}

// MARK: - Area Readiness

/// Per-area factual curriculum position and evidence availability for a student.
struct AreaReadiness: Identifiable, Codable {
    let id: UUID
    let area: String
    let sequence: String
    let currentLessonName: String?
    let currentLessonID: UUID?
    let nextLessonName: String?
    let nextLessonID: UUID?
    let proficiencySignal: ProficiencySignal
    let evidenceAvailability: EvidenceAvailability
    let activeWorkCount: Int
    let presentedInSequence: Int
    let totalInSequence: Int
    
    init(
        area: String,
        sequence: String,
        currentLessonName: String?,
        currentLessonID: UUID?,
        nextLessonName: String?,
        nextLessonID: UUID?,
        proficiencySignal: ProficiencySignal,
        evidenceAvailability: EvidenceAvailability,
        activeWorkCount: Int,
        presentedInSequence: Int,
        totalInSequence: Int
    ) {
        self.id = UUID()
        self.area = area
        self.sequence = sequence
        self.currentLessonName = currentLessonName
        self.currentLessonID = currentLessonID
        self.nextLessonName = nextLessonName
        self.nextLessonID = nextLessonID
        self.proficiencySignal = proficiencySignal
        self.evidenceAvailability = evidenceAvailability
        self.activeWorkCount = activeWorkCount
        self.presentedInSequence = presentedInSequence
        self.totalInSequence = totalInSequence
    }
}

// MARK: - Proficiency Signal

/// A factual planning signal. Strong states come only from explicit guide
/// decisions; ordinary presentation history never becomes mastery by inference.
enum ProficiencySignal: String, Codable {
    case notPresented
    case presented
    case practicing
    case proficient = "mastered"
    case needsMorePractice
    case needsReteaching
    
    var displayLabel: String {
        switch self {
        case .notPresented: return "Not Presented"
        case .presented: return "Presented"
        case .practicing: return "Practicing"
        case .proficient: return "Guide Confirmed"
        case .needsMorePractice: return "Needs Practice"
        case .needsReteaching: return "Needs Re-presentation"
        }
    }
}

// MARK: - Curriculum Map

/// Hierarchical representation of curriculum positions for a set of students.
struct CurriculumMap: Codable {
    var areas: [AreaMap]
    
    struct AreaMap: Identifiable, Codable {
        let id: UUID
        let area: String
        var groups: [SequenceMap]
        
        init(area: String, groups: [SequenceMap]) {
            self.id = UUID()
            self.area = area
            self.groups = groups
        }
    }
    
    struct SequenceMap: Identifiable, Codable {
        let id: UUID
        let sequence: String
        var lessons: [LessonPosition]
        let presentedCount: Int
        let totalCount: Int
        
        init(sequence: String, lessons: [LessonPosition], presentedCount: Int, totalCount: Int) {
            self.id = UUID()
            self.sequence = sequence
            self.lessons = lessons
            self.presentedCount = presentedCount
            self.totalCount = totalCount
        }
    }
    
    struct LessonPosition: Identifiable, Codable {
        let id: UUID
        let lessonID: UUID
        let lessonName: String
        let orderInSequence: Int
        var studentStatuses: [PresentationStatus]
        
        init(lessonID: UUID, lessonName: String, orderInSequence: Int, studentStatuses: [PresentationStatus]) {
            self.id = UUID()
            self.lessonID = lessonID
            self.lessonName = lessonName
            self.orderInSequence = orderInSequence
            self.studentStatuses = studentStatuses
        }
    }
    
    struct PresentationStatus: Codable {
        let studentID: UUID
        let studentName: String
        let proficiency: ProficiencySignal
    }
}

// MARK: - Teacher Decision

/// Teacher's response to a recommendation.
enum TeacherDecision: String, Codable {
    case accepted
    case rejected
    case modified
    case deferred
}

// MARK: - Recommendation Outcome

/// Outcome after a recommendation was accepted and applied.
enum RecommendationOutcome: String, Codable {
    case presented
    case deferred
    case cancelled
    case modified
}

// MARK: - Planning Response (API Parsing)

/// Intermediate type for parsing structured API responses.
struct PlanningResponse: Codable {
    let recommendations: [APIRecommendation]
    let groupingSuggestions: [APIGroupingSuggestion]?
    let summary: String?
    let followUpContext: String?
    
    struct APIRecommendation: Codable {
        let lessonName: String
        let area: String
        let sequence: String
        let studentNames: [String]
        let reasoning: String
        let confidence: Double?
        let priority: Int
        let suggestedDay: String?
    }
    
    struct APIGroupingSuggestion: Codable {
        let lessonName: String
        let studentNames: [String]
        let rationale: String
    }
}

// MARK: - Token Estimation

enum TokenEstimator {
    /// Rough estimate: ~4 characters per token
    static func estimateTokens(for text: String) -> Int {
        max(1, text.count / 4)
    }
    
    /// Check if text is within a token budget
    static func isWithinBudget(_ text: String, budget: Int) -> Bool {
        estimateTokens(for: text) <= budget
    }
}
