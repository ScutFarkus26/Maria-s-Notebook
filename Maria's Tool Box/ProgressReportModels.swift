// ProgressReportModels.swift
// SIMPLIFIED VERSION - Store arrays directly in SwiftData

import Foundation
import SwiftData

// MARK: - Enums
public enum ReportTerm: String, Codable, CaseIterable { case midYear, endYear }

public enum ReportRatingValue: String, Codable, CaseIterable {
    case four = "4"
    case three = "3"
    case two = "2"
    case one = "1"
    case x = "X"
}

// MARK: - Codable structures
public struct ReportRatingEntry: Codable, Identifiable, Hashable {
    public var id: String
    public var domain: String
    public var skillLabel: String
    public var midYear: ReportRatingValue?
    public var endYear: ReportRatingValue?

    public init(id: String, domain: String, skillLabel: String, midYear: ReportRatingValue? = nil, endYear: ReportRatingValue? = nil) {
        self.id = id
        self.domain = domain
        self.skillLabel = skillLabel
        self.midYear = midYear
        self.endYear = endYear
    }
}

public struct ReportComments: Codable, Hashable {
    public var midYearBySection: [String:String]
    public var endYearBySection: [String:String]
    public var midYearOverview: String
    public var midYearStrengths: String
    public var midYearAreasForGrowth: String
    public var midYearGoals: String
    public var midYearOutlook: String
    public var endYearOverview: String
    public var endYearStrengths: String
    public var endYearChallenges: String
    public var endYearCurrentStrategies: String
    public var endYearGoals: String
    public var endYearOutlook: String

    public init(
        midYearBySection: [String:String] = [:],
        endYearBySection: [String:String] = [:],
        midYearOverview: String = "",
        midYearStrengths: String = "",
        midYearAreasForGrowth: String = "",
        midYearGoals: String = "",
        midYearOutlook: String = "",
        endYearOverview: String = "",
        endYearStrengths: String = "",
        endYearChallenges: String = "",
        endYearCurrentStrategies: String = "",
        endYearGoals: String = "",
        endYearOutlook: String = ""
    ) {
        self.midYearBySection = midYearBySection
        self.endYearBySection = endYearBySection
        self.midYearOverview = midYearOverview
        self.midYearStrengths = midYearStrengths
        self.midYearAreasForGrowth = midYearAreasForGrowth
        self.midYearGoals = midYearGoals
        self.midYearOutlook = midYearOutlook
        self.endYearOverview = endYearOverview
        self.endYearStrengths = endYearStrengths
        self.endYearChallenges = endYearChallenges
        self.endYearCurrentStrategies = endYearCurrentStrategies
        self.endYearGoals = endYearGoals
        self.endYearOutlook = endYearOutlook
    }
}

// MARK: - SwiftData model
@Model public final class StudentProgressReport {
    public var id: UUID
    public var studentPersistentID: String
    public var templateName: String
    
    // ⭐️ KEY CHANGE: Store Data directly without computed properties
    // SwiftData will track changes to these properties
    private var _ratingsData: Data
    private var _commentsData: Data
    
    public var updatedAt: Date
    public var schoolYear: String
    public var teacher: String
    public var grade: String

    // Public interface uses computed properties but we force a new Data object every time
    public var ratings: [ReportRatingEntry] {
        get { (try? JSONDecoder().decode([ReportRatingEntry].self, from: _ratingsData)) ?? [] }
        set {
            // Force creation of new Data to trigger SwiftData change tracking
            if let encoded = try? JSONEncoder().encode(newValue) {
                _ratingsData = encoded
                updatedAt = Date()
            }
        }
    }

    public var comments: ReportComments {
        get { (try? JSONDecoder().decode(ReportComments.self, from: _commentsData)) ?? ReportComments() }
        set {
            // Force creation of new Data to trigger SwiftData change tracking
            if let encoded = try? JSONEncoder().encode(newValue) {
                _commentsData = encoded
                updatedAt = Date()
            }
        }
    }
    
    // Compatibility properties for export (deprecated but keeping for now)
    public var ratingsData: Data {
        get { _ratingsData }
        set { _ratingsData = newValue }
    }
    
    public var commentsData: Data {
        get { _commentsData }
        set { _commentsData = newValue }
    }

    public init(
        id: UUID = UUID(),
        studentPersistentID: String,
        templateName: String = "Yeshivas Yakir Li Progress Report",
        ratings: [ReportRatingEntry] = [],
        comments: ReportComments = ReportComments(),
        schoolYear: String = "2024-2025",
        teacher: String = "",
        grade: String = ""
    ) {
        self.id = id
        self.studentPersistentID = studentPersistentID
        self.templateName = templateName
        self._ratingsData = (try? JSONEncoder().encode(ratings)) ?? Data()
        self._commentsData = (try? JSONEncoder().encode(comments)) ?? Data()
        self.updatedAt = Date()
        self.schoolYear = schoolYear
        self.teacher = teacher
        self.grade = grade
    }
}

// MARK: - Convenience helpers
public enum StudentProgressReportStore {
    public static func fetchOrCreate(for studentID: UUID, using context: ModelContext) -> StudentProgressReport {
        let idString = studentID.uuidString
        let predicate = #Predicate<StudentProgressReport> { $0.studentPersistentID == idString }
        let descriptor = FetchDescriptor<StudentProgressReport>(predicate: predicate)
        if let fetched = try? context.fetch(descriptor), let report = fetched.first {
            return report
        }
        // Create with default schema
        let report = StudentProgressReport(
            studentPersistentID: idString,
            templateName: "Yeshivas Yakir Li Progress Report",
            ratings: ProgressReportSchema.defaultEntries(),
            comments: ReportComments()
        )
        context.insert(report)
        do { try context.save() } catch { /* ignore for first creation */ }
        return report
    }
}
