// ReportGeneratorService.swift
// Service for generating PDF reports from flagged notes
// swiftlint:disable file_length

import Foundation
import CoreData
import SwiftUI
import PDFKit
import OSLog

#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

struct ReportGeneratorService {
    private static let logger = Logger.reports

    // MARK: - Core Data API (Primary)

    /// Fetch flagged notes for a student within a date range (Core Data)
    func fetchReportNotes(
        for student: CDStudent,
        dateRange: ClosedRange<Date>,
        context: NSManagedObjectContext
    ) -> [CDNote] {
        let startDate = dateRange.lowerBound
        let endDate = dateRange.upperBound

        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "includeInReport == YES AND createdAt >= %@ AND createdAt <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.relationshipKeyPathsForPrefetching = ["studentLinks"]

        let allFlagged = context.safeFetch(request)

        // Filter to notes visible to this student
        guard let studentID = student.id else { return [] }
        return allFlagged.filter { note in
            note.scopeIsAll || note.searchIndexStudentID == studentID || note.scope.applies(to: studentID)
        }
    }

    // Deprecated SwiftData safeFetch helper removed.

    // MARK: - Report Options

    enum DateRangeOption: String, CaseIterable, Identifiable {
        case lastWeek = "Last 7 Days"
        case lastMonth = "Last 30 Days"
        case lastQuarter = "Last 90 Days"
        case thisSemester = "This Semester"
        case custom = "Custom Range"

        var id: String { rawValue }

        func dateRange(from today: Date = Date()) -> ClosedRange<Date> {
            let calendar = Calendar.current
            switch self {
            case .lastWeek:
                let start = calendar.date(byAdding: .day, value: -7, to: today) ?? today
                return start...today
            case .lastMonth:
                let start = calendar.date(byAdding: .day, value: -30, to: today) ?? today
                return start...today
            case .lastQuarter:
                let start = calendar.date(byAdding: .day, value: -90, to: today) ?? today
                return start...today
            case .thisSemester:
                // Approximate semester: 4 months
                let start = calendar.date(byAdding: .month, value: -4, to: today) ?? today
                return start...today
            case .custom:
                // Default to last 30 days for custom; caller should provide actual range
                let start = calendar.date(byAdding: .day, value: -30, to: today) ?? today
                return start...today
            }
        }
    }

    enum ReportStyle: String, CaseIterable, Identifiable {
        case progressReport = "Progress Report"
        case parentConference = "Parent Conference"
        case iepDocumentation = "IEP Documentation"

        var id: String { rawValue }

        var includesImages: Bool {
            switch self {
            case .progressReport: return true
            case .parentConference: return true
            case .iepDocumentation: return false
            }
        }

        var groupsByCategory: Bool {
            switch self {
            case .progressReport: return true
            case .parentConference: return false
            case .iepDocumentation: return true
            }
        }
    }

    // Deprecated SwiftData fetchReportNotes removed - use Core Data overload.

    // MARK: - Generate PDF

    /// Enhanced PDF generation with optional AI narrative, attendance, and mastery data.
    // swiftlint:disable:next function_body_length
    func generatePDF(
        student: CDStudent,
        notes: [CDNote],
        style: ReportStyle,
        dateRange: ClosedRange<Date>,
        aiNarrative: String? = nil,
        attendanceRate: Double? = nil,
        daysPresent: Int = 0,
        totalSchoolDays: Int = 0,
        masteryBreakdown: AIReportService.MasteryBreakdown? = nil,
        lessonCount: Int = 0
    ) -> Data {
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - (margin * 2)

        var pdfData = Data()

        #if canImport(UIKit)
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )

        pdfData = renderer.pdfData { context in
            context.beginPage()

            var currentY: CGFloat = margin

            // Header
            currentY = drawHeader(
                student: student,
                style: style,
                dateRange: dateRange,
                pageWidth: pageWidth,
                margin: margin,
                currentY: currentY
            )

            currentY += 20

            // Stats summary (attendance + mastery + lessons)
            if attendanceRate != nil || masteryBreakdown != nil || lessonCount > 0 {
                currentY = drawStatsSummary(
                    attendanceRate: attendanceRate,
                    daysPresent: daysPresent,
                    totalSchoolDays: totalSchoolDays,
                    mastery: masteryBreakdown,
                    lessonCount: lessonCount,
                    margin: margin,
                    contentWidth: contentWidth,
                    currentY: currentY,
                    context: context
                )
                currentY += 16
            }

            // AI narrative summary
            if let narrative = aiNarrative {
                if currentY > pageHeight - margin - 200 {
                    context.beginPage()
                    currentY = margin
                }
                currentY = drawAINarrative(
                    narrative: narrative,
                    margin: margin,
                    contentWidth: contentWidth,
                    currentY: currentY
                )
                currentY += 20
            }

            // Notes content
            let groupedNotes: [(String, [CDNote])]
            if style.groupsByCategory {
                groupedNotes = groupNotesByCategory(notes)
            } else {
                groupedNotes = [("Notes", notes)]
            }

            for (categoryName, categoryNotes) in groupedNotes {
                // Category header
                if style.groupsByCategory && !categoryNotes.isEmpty {
                    let categoryAttrs: [NSAttributedString.Key: Any] = [
                        .font: PlatformFont.boldSystemFont(ofSize: 14),
                        .foregroundColor: PlatformColor.label
                    ]
                    let categoryString = NSAttributedString(string: categoryName, attributes: categoryAttrs)
                    categoryString.draw(at: CGPoint(x: margin, y: currentY))
                    currentY += 24
                }

                // Draw each note
                for note in categoryNotes {
                    // Check if we need a new page
                    if currentY > pageHeight - margin - 100 {
                        context.beginPage()
                        currentY = margin
                    }

                    currentY = drawNote(
                        note: note,
                        margin: margin,
                        contentWidth: contentWidth,
                        currentY: currentY
                    )

                    currentY += 16
                }

                currentY += 8
            }

            // Footer
            drawFooter(
                pageWidth: pageWidth,
                pageHeight: pageHeight,
                margin: margin
            )
        }
        #elseif canImport(AppKit)
        // macOS: Use NSPrintOperation approach or simple text-based PDF
        // For simplicity, use a basic approach with NSAttributedString
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: pageWidth, height: pageHeight)
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin

        // Build a simple text document
        let reportText = buildReportText(
            student: student,
            notes: notes,
            style: style,
            dateRange: dateRange,
            aiNarrative: aiNarrative,
            attendanceRate: attendanceRate,
            daysPresent: daysPresent,
            totalSchoolDays: totalSchoolDays,
            masteryBreakdown: masteryBreakdown,
            lessonCount: lessonCount
        )

        // Create PDF using CGContext
        let pdfDocument = PDFDocument()

        // Use a simpler approach - create PDF data directly
        if let pdfPage = createPDFPage(
            from: reportText,
            pageSize: NSSize(width: pageWidth, height: pageHeight),
            margin: margin
        ) {
            pdfDocument.insert(pdfPage, at: 0)
            pdfData = pdfDocument.dataRepresentation() ?? Data()
        }
        #endif

        return pdfData
    }

}

// MARK: - Drawing Helpers (iOS)

extension ReportGeneratorService {
    #if canImport(UIKit)
    // swiftlint:disable:next function_parameter_count
    private func drawHeader(
        student: CDStudent,
        style: ReportStyle,
        dateRange: ClosedRange<Date>,
        pageWidth: CGFloat,
        margin: CGFloat,
        currentY: CGFloat
    ) -> CGFloat {
        var y = currentY

        // Title
        let title = "\(student.firstName) - \(style.rawValue)"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.boldSystemFont(ofSize: 18),
            .foregroundColor: PlatformColor.label
        ]
        let titleString = NSAttributedString(string: title, attributes: titleAttrs)
        titleString.draw(at: CGPoint(x: margin, y: y))
        y += 28

        // Date range
        let startStr = DateFormatters.mediumDate.string(from: dateRange.lowerBound)
        let endStr = DateFormatters.mediumDate.string(from: dateRange.upperBound)
        let dateRangeText = "\(startStr) - \(endStr)"
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 12),
            .foregroundColor: PlatformColor.secondaryLabel
        ]
        let dateString = NSAttributedString(string: dateRangeText, attributes: dateAttrs)
        dateString.draw(at: CGPoint(x: margin, y: y))
        y += 20

        // Divider line
        let context = UIGraphicsGetCurrentContext()
        context?.setStrokeColor(PlatformColor.separator.cgColor)
        context?.setLineWidth(0.5)
        context?.move(to: CGPoint(x: margin, y: y))
        context?.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        context?.strokePath()
        y += 4

        return y
    }

    private func drawNote(
        note: CDNote,
        margin: CGFloat,
        contentWidth: CGFloat,
        currentY: CGFloat
    ) -> CGFloat {
        var y = currentY

        // Date
        let dateText = DateFormatters.shortDateTime.string(from: note.createdAt ?? Date())
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 10),
            .foregroundColor: PlatformColor.secondaryLabel
        ]
        let dateString = NSAttributedString(string: dateText, attributes: dateAttrs)
        dateString.draw(at: CGPoint(x: margin, y: y))
        y += 14

        // CDNote body
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 11),
            .foregroundColor: PlatformColor.label
        ]
        let bodyString = NSAttributedString(string: note.body, attributes: bodyAttrs)
        let bodyRect = CGRect(x: margin, y: y, width: contentWidth, height: .greatestFiniteMagnitude)
        let boundingRect = bodyString.boundingRect(
            with: bodyRect.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        bodyString.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: boundingRect.height))
        y += boundingRect.height + 4

        // Tags badge
        let tagNames = ((note.tags as? [String]) ?? []).map { TagHelper.tagName($0) }.joined(separator: ", ")
        let categoryText = tagNames.isEmpty ? "[General]" : "[\(tagNames)]"
        let categoryAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 9),
            .foregroundColor: PlatformColor.systemBlue
        ]
        let categoryString = NSAttributedString(string: categoryText, attributes: categoryAttrs)
        categoryString.draw(at: CGPoint(x: margin, y: y))
        y += 14

        return y
    }

    // swiftlint:disable:next function_parameter_count
    private func drawStatsSummary(
        attendanceRate: Double?,
        daysPresent: Int,
        totalSchoolDays: Int,
        mastery: AIReportService.MasteryBreakdown?,
        lessonCount: Int,
        margin: CGFloat,
        contentWidth: CGFloat,
        currentY: CGFloat,
        context: UIGraphicsPDFRendererContext
    ) -> CGFloat {
        var y = currentY

        let sectionAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.boldSystemFont(ofSize: 13),
            .foregroundColor: PlatformColor.label
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 11),
            .foregroundColor: PlatformColor.label
        ]

        NSAttributedString(string: "Overview", attributes: sectionAttrs)
            .draw(at: CGPoint(x: margin, y: y))
        y += 20

        var statLines: [String] = []
        if let rate = attendanceRate {
            statLines.append("Attendance: \(daysPresent)/\(totalSchoolDays) days (\(Int(rate * 100))%)")
        }
        if lessonCount > 0 {
            statLines.append("Lessons Presented: \(lessonCount)")
        }
        if let m = mastery, m.total > 0 {
            statLines.append(
                "Mastery: \(m.proficient) mastered, \(m.practicing) practicing, " +
                "\(m.presented) presented, \(m.readyForAssessment) ready for assessment"
            )
        }

        for line in statLines {
            let attrStr = NSAttributedString(string: "• \(line)", attributes: valueAttrs)
            attrStr.draw(at: CGPoint(x: margin + 8, y: y))
            y += 16
        }

        // Divider
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setStrokeColor(PlatformColor.separator.cgColor)
        ctx?.setLineWidth(0.5)
        ctx?.move(to: CGPoint(x: margin, y: y + 4))
        ctx?.addLine(to: CGPoint(x: margin + contentWidth, y: y + 4))
        ctx?.strokePath()
        y += 8

        return y
    }

    private func drawAINarrative(
        narrative: String,
        margin: CGFloat,
        contentWidth: CGFloat,
        currentY: CGFloat
    ) -> CGFloat {
        var y = currentY

        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.boldSystemFont(ofSize: 13),
            .foregroundColor: PlatformColor.label
        ]
        NSAttributedString(string: "Summary", attributes: headingAttrs)
            .draw(at: CGPoint(x: margin, y: y))
        y += 20

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 11),
            .foregroundColor: PlatformColor.label
        ]
        let bodyString = NSAttributedString(string: narrative, attributes: bodyAttrs)
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: .greatestFiniteMagnitude)
        let boundingRect = bodyString.boundingRect(
            with: rect.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        bodyString.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: boundingRect.height))
        y += boundingRect.height + 8

        // Divider
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setStrokeColor(PlatformColor.separator.cgColor)
        ctx?.setLineWidth(0.5)
        ctx?.move(to: CGPoint(x: margin, y: y))
        ctx?.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        ctx?.strokePath()
        y += 4

        return y
    }

    private func drawFooter(
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        margin: CGFloat
    ) {
        let footerY = pageHeight - margin + 10
        let generatedText = "Generated by Maria's Notebook"
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 8),
            .foregroundColor: PlatformColor.secondaryLabel
        ]
        let footerString = NSAttributedString(string: generatedText, attributes: footerAttrs)
        let footerSize = footerString.size()
        footerString.draw(at: CGPoint(x: (pageWidth - footerSize.width) / 2, y: footerY))
    }
    #endif

}

// MARK: - macOS Helpers

extension ReportGeneratorService {
    #if canImport(AppKit)
    private func buildReportText(
        student: CDStudent,
        notes: [CDNote],
        style: ReportStyle,
        dateRange: ClosedRange<Date>,
        aiNarrative: String?,
        attendanceRate: Double?,
        daysPresent: Int,
        totalSchoolDays: Int,
        masteryBreakdown: AIReportService.MasteryBreakdown?,
        lessonCount: Int
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        // swiftlint:disable line_length
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.labelColor]
        result.append(NSAttributedString(string: "\(student.firstName) - \(style.rawValue)\n\n", attributes: titleAttrs))
        // swiftlint:enable line_length
        let rangeStart = DateFormatters.mediumDate.string(from: dateRange.lowerBound)
        let rangeEnd = DateFormatters.mediumDate.string(from: dateRange.upperBound)
        // swiftlint:disable:next line_length
        let dateAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        result.append(NSAttributedString(string: "\(rangeStart) - \(rangeEnd)\n\n", attributes: dateAttrs))
        result.append(NSAttributedString(string: "─────────────────────────────────────\n\n"))
        appendStatsText(
            to: result,
            attendanceRate: attendanceRate,
            daysPresent: daysPresent,
            totalSchoolDays: totalSchoolDays,
            mastery: masteryBreakdown,
            lessonCount: lessonCount
        )
        if let narrative = aiNarrative {
            appendNarrativeText(to: result, narrative: narrative)
        }
        appendGroupedNotesText(to: result, notes: notes, style: style)
        // swiftlint:disable:next line_length
        let footerAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.secondaryLabelColor]
        result.append(NSAttributedString(string: "\n\nGenerated by Maria's Notebook", attributes: footerAttrs))
        return result
    }

    private func appendGroupedNotesText(to result: NSMutableAttributedString, notes: [CDNote], style: ReportStyle) {
        let groupedNotes: [(String, [CDNote])] = style.groupsByCategory ? groupNotesByCategory(notes) : [("Notes", notes)]
        for (categoryName, categoryNotes) in groupedNotes {
            if style.groupsByCategory && !categoryNotes.isEmpty {
                // swiftlint:disable:next line_length
                let categoryAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]
                result.append(NSAttributedString(string: "\(categoryName)\n", attributes: categoryAttrs))
            }
            for note in categoryNotes {
                // swiftlint:disable line_length
                let noteDateAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
                result.append(NSAttributedString(string: "\(DateFormatters.shortDateTime.string(from: note.createdAt ?? Date()))\n", attributes: noteDateAttrs))
                let bodyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
                result.append(NSAttributedString(string: "\(note.body)\n", attributes: bodyAttrs))
                let tagAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.systemBlue]
                let tagLabel = note.tagsArray.map { TagHelper.tagName($0) }.joined(separator: ", ")
                result.append(NSAttributedString(string: "[\(tagLabel.isEmpty ? "General" : tagLabel)]\n\n", attributes: tagAttrs))
                // swiftlint:enable line_length
            }
        }
    }

    private func appendStatsText(
        to result: NSMutableAttributedString,
        attendanceRate: Double?,
        daysPresent: Int,
        totalSchoolDays: Int,
        mastery: AIReportService.MasteryBreakdown?,
        lessonCount: Int
    ) {
        guard attendanceRate != nil || mastery != nil || lessonCount > 0 else { return }

        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]

        result.append(NSAttributedString(string: "Overview\n", attributes: headingAttrs))

        if let rate = attendanceRate {
            let line = "• Attendance: \(daysPresent)/\(totalSchoolDays) days (\(Int(rate * 100))%)\n"
            result.append(NSAttributedString(string: line, attributes: valueAttrs))
        }
        if lessonCount > 0 {
            result.append(NSAttributedString(string: "• Lessons Presented: \(lessonCount)\n", attributes: valueAttrs))
        }
        if let m = mastery, m.total > 0 {
            let line = "• Mastery: \(m.proficient) mastered, \(m.practicing) practicing, " +
                "\(m.presented) presented, \(m.readyForAssessment) ready for assessment\n"
            result.append(NSAttributedString(string: line, attributes: valueAttrs))
        }
        result.append(NSAttributedString(string: "\n"))
    }

    private func appendNarrativeText(to result: NSMutableAttributedString, narrative: String) {
        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]

        result.append(NSAttributedString(string: "Summary\n", attributes: headingAttrs))
        result.append(NSAttributedString(string: "\(narrative)\n\n", attributes: bodyAttrs))
        result.append(NSAttributedString(string: "─────────────────────────────────────\n\n"))
    }

    private func createPDFPage(
        from attributedString: NSAttributedString, pageSize: NSSize, margin: CGFloat
    ) -> PDFPage? {
        // Create a simple PDF page from attributed string
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let contentSize = NSSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let textContainer = NSTextContainer(size: contentSize)
        layoutManager.addTextContainer(textContainer)

        // Create PDF data
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        context.beginPDFPage(nil)

        // Flip coordinate system
        context.translateBy(x: 0, y: pageSize.height)
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw text
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: CGPoint(x: margin, y: margin))

        NSGraphicsContext.restoreGraphicsState()

        context.endPDFPage()
        context.closePDF()

        // Convert to PDFPage
        if let pdfDocument = PDFDocument(data: pdfData as Data),
           let page = pdfDocument.page(at: 0) {
            return page
        }
        return nil
    }
    #endif

}

// MARK: - Common Helpers

extension ReportGeneratorService {
    private func groupNotesByCategory(_ notes: [CDNote]) -> [(String, [CDNote])] {
        // Group notes by their first tag (or "General" if untagged)
        var grouped: [String: [CDNote]] = [:]
        for note in notes {
            if let firstTag = (note.tags as? [String])?.first {
                let tagName = TagHelper.tagName(firstTag)
                grouped[tagName, default: []].append(note)
            } else {
                grouped["General", default: []].append(note)
            }
        }

        // Return sorted alphabetically
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
