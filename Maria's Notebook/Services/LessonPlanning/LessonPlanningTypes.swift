// swiftlint:disable file_length
import Foundation

// MARK: - Planning Depth

/// Controls how many AI pipeline steps to run and the corresponding cost/detail tradeoff.
enum PlanningDepth: String, Codable, CaseIterable, Identifiable {
    /// Steps 1-2 only: local readiness + gap analysis (~$0.01)
    case quick
    /// Steps 1-3: adds plan synthesis with day scheduling (~$0.02-0.03)
    case standard
    /// Steps 1-4: adds whole-class week optimization (~$0.04-0.06)
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
        case .quick: return "Fast suggestions based on readiness"
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
    case assessingReadiness
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
        case .assessingReadiness: return "Assessing readiness..."
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

/// A single AI-generated lesson recommendation.
struct LessonRecommendation: Identifiable, Codable {
    let id: UUID
    let lessonID: UUID
    let lessonName: String
    let subject: String
    let group: String
    let studentIDs: [UUID]
    let studentNames: [String]
    let reasoning: String
    let confidence: Double
    let priority: Int
    let suggestedDay: String?
    var decision: TeacherDecision?
    
    init(
        lessonID: UUID,
        lessonName: String,
        subject: String,
        group: String,
        studentIDs: [UUID],
        studentNames: [String],
        reasoning: String,
        confidence: Double,
        priority: Int,
        suggestedDay: String? = nil
    ) {
        self.id = UUID()
        self.lessonID = lessonID
        self.lessonName = lessonName
        self.subject = subject
        self.group = group
        self.studentIDs = studentIDs
        self.studentNames = studentNames
        self.reasoning = reasoning
        self.confidence = confidence
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

// MARK: - CDStudent Readiness Profile

/// Locally-computed profile summarizing a student's readiness for new lessons.
struct StudentReadinessProfile: Identifiable, Codable {
    let id: UUID
    let studentID: UUID
    let studentName: String
    let level: String
    var subjectReadiness: [SubjectReadiness]
    let practiceQualityAvg: Double?
    let independenceAvg: Double?
    let daysSinceLastPresentation: Int?
    let activeWorkCount: Int
    let behavioralFlags: [String]
    
    init(
        studentID: UUID,
        studentName: String,
        level: String,
        subjectReadiness: [SubjectReadiness],
        practiceQualityAvg: Double?,
        independenceAvg: Double?,
        daysSinceLastPresentation: Int?,
        activeWorkCount: Int,
        behavioralFlags: [String]
    ) {
        self.id = UUID()
        self.studentID = studentID
        self.studentName = studentName
        self.level = level
        self.subjectReadiness = subjectReadiness
        self.practiceQualityAvg = practiceQualityAvg
        self.independenceAvg = independenceAvg
        self.daysSinceLastPresentation = daysSinceLastPresentation
        self.activeWorkCount = activeWorkCount
        self.behavioralFlags = behavioralFlags
    }
}

// MARK: - Subject Readiness

/// Per-subject readiness data for a single student.
struct SubjectReadiness: Identifiable, Codable {
    let id: UUID
    let subject: String
    let group: String
    let currentLessonName: String?
    let currentLessonID: UUID?
    let nextLessonName: String?
    let nextLessonID: UUID?
    let proficiencySignal: ProficiencySignal
    let activeWorkCount: Int
    let completedInGroup: Int
    let totalInGroup: Int
    
    init(
        subject: String,
        group: String,
        currentLessonName: String?,
        currentLessonID: UUID?,
        nextLessonName: String?,
        nextLessonID: UUID?,
        proficiencySignal: ProficiencySignal,
        activeWorkCount: Int,
        completedInGroup: Int,
        totalInGroup: Int
    ) {
        self.id = UUID()
        self.subject = subject
        self.group = group
        self.currentLessonName = currentLessonName
        self.currentLessonID = currentLessonID
        self.nextLessonName = nextLessonName
        self.nextLessonID = nextLessonID
        self.proficiencySignal = proficiencySignal
        self.activeWorkCount = activeWorkCount
        self.completedInGroup = completedInGroup
        self.totalInGroup = totalInGroup
    }
}

// MARK: - Proficiency Signal

/// Indicates a student's proficiency status for a particular curriculum position.
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
        case .proficient: return "Mastered"
        case .needsMorePractice: return "Needs Practice"
        case .needsReteaching: return "Needs Reteaching"
        }
    }
}

// MARK: - Curriculum Map

/// Hierarchical representation of curriculum positions for a set of students.
struct CurriculumMap: Codable {
    var subjects: [SubjectMap]
    
    struct SubjectMap: Identifiable, Codable {
        let id: UUID
        let subject: String
        var groups: [GroupMap]
        
        init(subject: String, groups: [GroupMap]) {
            self.id = UUID()
            self.subject = subject
            self.groups = groups
        }
    }
    
    struct GroupMap: Identifiable, Codable {
        let id: UUID
        let group: String
        var lessons: [LessonPosition]
        let completedCount: Int
        let totalCount: Int
        
        init(group: String, lessons: [LessonPosition], completedCount: Int, totalCount: Int) {
            self.id = UUID()
            self.group = group
            self.lessons = lessons
            self.completedCount = completedCount
            self.totalCount = totalCount
        }
    }
    
    struct LessonPosition: Identifiable, Codable {
        let id: UUID
        let lessonID: UUID
        let lessonName: String
        let orderInGroup: Int
        var studentStatuses: [PresentationStatus]
        
        init(lessonID: UUID, lessonName: String, orderInGroup: Int, studentStatuses: [PresentationStatus]) {
            self.id = UUID()
            self.lessonID = lessonID
            self.lessonName = lessonName
            self.orderInGroup = orderInGroup
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
        let subject: String
        let group: String
        let studentNames: [String]
        let reasoning: String
        let confidence: Double
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
