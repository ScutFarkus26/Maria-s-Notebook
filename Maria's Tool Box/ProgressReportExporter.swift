import Foundation
import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

enum ProgressReportExporter {
    enum ExportError: Error { case templateMissing, userCancelled, mergeFailed(String) }

    // Name of the template in the bundle
    private static let templateName = "Blank 24-25 Progress Report"

    // MARK: - Public API
    #if os(macOS)
    @MainActor
    static func exportDOCXViaSavePanel(report: StudentProgressReport, student: Student) throws {
        guard let templateURL = Bundle.main.url(forResource: templateName, withExtension: "docx") else {
            throw ExportError.templateMissing
        }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["docx"]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = safeFileName(student: student, suffix: "DOCX") + ".docx"
        let response = panel.runModal()
        guard response == .OK, let outURL = panel.url else { throw ExportError.userCancelled }

        let replacements = buildReplacements(report: report, student: student)
        do {
            try DocxTemplateMerger.merge(templateURL: templateURL, outputURL: outURL, replacements: replacements)
        } catch {
            throw ExportError.mergeFailed(error.localizedDescription)
        }
        NSWorkspace.shared.activateFileViewerSelecting([outURL])
    }
    #endif

    // MARK: - Replacements
    static func buildReplacements(report: StudentProgressReport, student: Student) -> [String: String] {
        var map: [String: String] = [:]
        // Header
        map["{{STUDENT_NAME}}"] = student.fullName
        map["{{TEACHER}}"] = report.teacher
        map["{{SCHOOL_YEAR}}"] = report.schoolYear
        map["{{GRADE}}"] = report.grade

        // Ratings
        for entry in report.ratings {
            let id = entry.id.uppercased()
            map["{{RATING_\(id)_MID}}"] = entry.midYear?.rawValue ?? ""
            map["{{RATING_\(id)_END}}"] = entry.endYear?.rawValue ?? ""
        }

        // Section comments
        for (section, text) in report.comments.midYearBySection { map["{{COMMENT_\(section.uppercased())_MID}}"] = text }
        for (section, text) in report.comments.endYearBySection { map["{{COMMENT_\(section.uppercased())_END}}"] = text }

        // Mid-Year summary
        map["{{MID_OVERVIEW}}"] = report.comments.midYearOverview
        map["{{MID_STRENGTHS}}"] = report.comments.midYearStrengths
        map["{{MID_GROWTH}}"] = report.comments.midYearAreasForGrowth
        map["{{MID_GOALS}}"] = report.comments.midYearGoals
        map["{{MID_OUTLOOK}}"] = report.comments.midYearOutlook

        // End-of-Year narrative
        map["{{END_OVERVIEW}}"] = report.comments.endYearOverview
        map["{{END_STRENGTHS}}"] = report.comments.endYearStrengths
        map["{{END_CHALLENGES}}"] = report.comments.endYearChallenges
        map["{{END_STRATEGIES}}"] = report.comments.endYearCurrentStrategies
        map["{{END_GOALS}}"] = report.comments.endYearGoals
        map["{{END_OUTLOOK}}"] = report.comments.endYearOutlook

        return map
    }

    // MARK: - Helpers
    private static func safeFileName(student: Student, suffix: String) -> String {
        let base = "\(student.fullName) - Progress Report"
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|\n\r")
        let cleaned = base.components(separatedBy: invalid).joined(separator: " ")
        return cleaned + " (\(suffix))"
    }
}
