import Foundation
import CoreData
import OSLog

@objc(DevelopmentSnapshotEntity)
public class DevelopmentSnapshotEntity: NSManagedObject {
    // MARK: - Attributes (Identity & Metadata)
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var generatedAt: Date?
    @NSManaged public var lookbackDays: Int64
    @NSManaged public var analysisVersion: String

    // MARK: - Attributes (Summary)
    @NSManaged public var overallProgress: String
    @NSManaged public var keyStrengthsData: Data?
    @NSManaged public var areasForGrowthData: Data?
    @NSManaged public var developmentalMilestonesData: Data?

    // MARK: - Attributes (Insights)
    @NSManaged public var observedPatternsData: Data?
    @NSManaged public var behavioralTrendsData: Data?
    @NSManaged public var socialEmotionalInsightsData: Data?

    // MARK: - Attributes (Recommendations)
    @NSManaged public var recommendedNextLessonsData: Data?
    @NSManaged public var suggestedPracticeFocusData: Data?
    @NSManaged public var interventionSuggestionsData: Data?

    // MARK: - Attributes (Metrics)
    @NSManaged public var totalNotesAnalyzed: Int64
    @NSManaged public var practiceSessionsAnalyzed: Int64
    @NSManaged public var workCompletionsAnalyzed: Int64
    @NSManaged public var averagePracticeQuality: Double
    @NSManaged public var independenceLevel: Double

    // MARK: - Attributes (Raw Data & User)
    @NSManaged public var rawAnalysisJSON: String
    @NSManaged public var userNotes: String
    @NSManaged public var isReviewed: Bool
    @NSManaged public var sharedWithParents: Bool
    @NSManaged public var sharedAt: Date?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "DevelopmentSnapshot", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.generatedAt = Date()
        self.lookbackDays = 30
        self.analysisVersion = "1.0"
        self.overallProgress = ""
        self.keyStrengthsData = nil
        self.areasForGrowthData = nil
        self.developmentalMilestonesData = nil
        self.observedPatternsData = nil
        self.behavioralTrendsData = nil
        self.socialEmotionalInsightsData = nil
        self.recommendedNextLessonsData = nil
        self.suggestedPracticeFocusData = nil
        self.interventionSuggestionsData = nil
        self.totalNotesAnalyzed = 0
        self.practiceSessionsAnalyzed = 0
        self.workCompletionsAnalyzed = 0
        self.averagePracticeQuality = 0
        self.independenceLevel = 0
        self.rawAnalysisJSON = ""
        self.userNotes = ""
        self.isReviewed = false
        self.sharedWithParents = false
        self.sharedAt = nil
    }
}

// MARK: - Computed Properties (JSON Array Accessors)
extension DevelopmentSnapshotEntity {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MariasNotebook", category: "DevelopmentSnapshotEntity")

    var keyStrengths: [String] {
        get { Self.decodeStringArray(from: keyStrengthsData) }
        set { keyStrengthsData = Self.encodeStringArray(newValue) }
    }

    var areasForGrowth: [String] {
        get { Self.decodeStringArray(from: areasForGrowthData) }
        set { areasForGrowthData = Self.encodeStringArray(newValue) }
    }

    var developmentalMilestones: [String] {
        get { Self.decodeStringArray(from: developmentalMilestonesData) }
        set { developmentalMilestonesData = Self.encodeStringArray(newValue) }
    }

    var observedPatterns: [String] {
        get { Self.decodeStringArray(from: observedPatternsData) }
        set { observedPatternsData = Self.encodeStringArray(newValue) }
    }

    var behavioralTrends: [String] {
        get { Self.decodeStringArray(from: behavioralTrendsData) }
        set { behavioralTrendsData = Self.encodeStringArray(newValue) }
    }

    var socialEmotionalInsights: [String] {
        get { Self.decodeStringArray(from: socialEmotionalInsightsData) }
        set { socialEmotionalInsightsData = Self.encodeStringArray(newValue) }
    }

    var recommendedNextLessons: [String] {
        get { Self.decodeStringArray(from: recommendedNextLessonsData) }
        set { recommendedNextLessonsData = Self.encodeStringArray(newValue) }
    }

    var suggestedPracticeFocus: [String] {
        get { Self.decodeStringArray(from: suggestedPracticeFocusData) }
        set { suggestedPracticeFocusData = Self.encodeStringArray(newValue) }
    }

    var interventionSuggestions: [String] {
        get { Self.decodeStringArray(from: interventionSuggestionsData) }
        set { interventionSuggestionsData = Self.encodeStringArray(newValue) }
    }

    // MARK: - Helper Properties

    /// Returns the student UUID from the stored string
    var studentUUID: UUID? {
        UUID(uuidString: studentID)
    }

    /// Returns true if this snapshot has actionable intervention suggestions
    var hasInterventions: Bool {
        !interventionSuggestions.isEmpty
    }

    /// Returns true if this snapshot contains sufficient data for meaningful analysis
    var hasSufficientData: Bool {
        totalNotesAnalyzed >= 3 || practiceSessionsAnalyzed >= 2
    }

    /// Returns a formatted summary for display
    var displaySummary: String {
        let dateStr = generatedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
        return """
        Generated: \(dateStr)
        Period: \(lookbackDays) days
        Data: \(totalNotesAnalyzed) notes, \(practiceSessionsAnalyzed) sessions, \(workCompletionsAnalyzed) completions
        """
    }

    // MARK: - Private Encoding/Decoding

    private static func decodeStringArray(from data: Data?) -> [String] {
        guard let data else { return [] }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            logger.warning("Failed to decode string array: \(error.localizedDescription)")
            return []
        }
    }

    private static func encodeStringArray(_ array: [String]) -> Data? {
        do {
            return try JSONEncoder().encode(array)
        } catch {
            logger.warning("Failed to encode string array: \(error.localizedDescription)")
            return nil
        }
    }
}
