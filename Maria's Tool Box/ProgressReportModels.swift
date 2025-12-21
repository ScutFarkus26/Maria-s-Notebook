// ProgressReportModels.swift
// Data model for per-student progress reports with ratings and comments.

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
    public var id: String              // stable slug: "kriah_fluency", "ela_reads_fluently_expression", etc.
    public var domain: String          // "Kriah", "ELA", "Math", etc.
    public var skillLabel: String      // the exact label shown in UI
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
    public var midYearBySection: [String:String] // e.g. "Kriah" -> comment
    public var endYearBySection: [String:String]

    // Mid-Year summary fields from the template
    public var midYearOverview: String
    public var midYearStrengths: String
    public var midYearAreasForGrowth: String
    public var midYearGoals: String
    public var midYearOutlook: String

    // End-of-year narrative block fields (keep as separate fields)
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
    public var studentPersistentID: String     // UUID string of Student.id
    public var templateName: String            // e.g., "Yeshivas Yakir Li Progress Report"
    public var ratingsData: Data               // Codable [ReportRatingEntry]
    public var commentsData: Data              // Codable ReportComments
    public var updatedAt: Date

    // Header fields for export (persisted)
    public var schoolYear: String
    public var teacher: String
    public var grade: String

    // Computed projections
    public var ratings: [ReportRatingEntry] {
        get { (try? JSONDecoder().decode([ReportRatingEntry].self, from: ratingsData)) ?? [] }
        set { ratingsData = (try? JSONEncoder().encode(newValue)) ?? Data() ; touch() }
    }

    public var comments: ReportComments {
        get { (try? JSONDecoder().decode(ReportComments.self, from: commentsData)) ?? ReportComments() }
        set { commentsData = (try? JSONEncoder().encode(newValue)) ?? Data() ; touch() }
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
        self.ratingsData = (try? JSONEncoder().encode(ratings)) ?? Data()
        self.commentsData = (try? JSONEncoder().encode(comments)) ?? Data()
        self.updatedAt = Date()
        self.schoolYear = schoolYear
        self.teacher = teacher
        self.grade = grade
    }

    private func touch() { updatedAt = Date() }
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
