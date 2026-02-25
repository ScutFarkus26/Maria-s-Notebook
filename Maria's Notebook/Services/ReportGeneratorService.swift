// ReportGeneratorService.swift
// Service for generating PDF reports from flagged notes

import Foundation
import SwiftData
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

    // MARK: - Helper Methods

    private func safeFetch<T>(_ descriptor: FetchDescriptor<T>, context: ModelContext, contextName: String = #function) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch \(String(describing: T.self), privacy: .public) in \(contextName, privacy: .public): \(error, privacy: .public)")
            return []
        }
    }

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

    // MARK: - Fetch Notes

    func fetchReportNotes(
        for student: Student,
        dateRange: ClosedRange<Date>,
        context: ModelContext
    ) -> [Note] {
        let startDate = dateRange.lowerBound
        let endDate = dateRange.upperBound

        // Fetch notes that are flagged for report and within date range
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { note in
                note.includeInReport == true &&
                note.createdAt >= startDate &&
                note.createdAt <= endDate
            },
            sortBy: [SortDescriptor(\Note.createdAt, order: .reverse)]
        )

        let allFlagged = safeFetch(descriptor, context: context, contextName: "fetchReportNotes")

        // Filter to notes visible to this student
        return allFlagged.filter { note in
            note.scopeIsAll || note.searchIndexStudentID == student.id || note.scope.applies(to: student.id)
        }
    }

    // MARK: - Generate PDF

    func generatePDF(
        student: Student,
        notes: [Note],
        style: ReportStyle,
        dateRange: ClosedRange<Date>
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

            // Notes content
            let groupedNotes: [(String, [Note])]
            if style.groupsByCategory {
                groupedNotes = groupNotesByCategory(notes)
            } else {
                groupedNotes = [("Notes", notes)]
            }

            for (categoryName, categoryNotes) in groupedNotes {
                // Category header
                if style.groupsByCategory && categoryNotes.count > 0 {
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
            dateRange: dateRange
        )

        // Create PDF using CGContext
        let pdfDocument = PDFDocument()

        // Use a simpler approach - create PDF data directly
        if let pdfPage = createPDFPage(from: reportText, pageSize: NSSize(width: pageWidth, height: pageHeight), margin: margin) {
            pdfDocument.insert(pdfPage, at: 0)
            pdfData = pdfDocument.dataRepresentation() ?? Data()
        }
        #endif

        return pdfData
    }

    // MARK: - Drawing Helpers (iOS)

    #if canImport(UIKit)
    private func drawHeader(
        student: Student,
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateRangeText = "\(dateFormatter.string(from: dateRange.lowerBound)) - \(dateFormatter.string(from: dateRange.upperBound))"
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
        note: Note,
        margin: CGFloat,
        contentWidth: CGFloat,
        currentY: CGFloat
    ) -> CGFloat {
        var y = currentY

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let dateText = dateFormatter.string(from: note.createdAt)
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 10),
            .foregroundColor: PlatformColor.secondaryLabel
        ]
        let dateString = NSAttributedString(string: dateText, attributes: dateAttrs)
        dateString.draw(at: CGPoint(x: margin, y: y))
        y += 14

        // Note body
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 11),
            .foregroundColor: PlatformColor.label
        ]
        let bodyString = NSAttributedString(string: note.body, attributes: bodyAttrs)
        let bodyRect = CGRect(x: margin, y: y, width: contentWidth, height: .greatestFiniteMagnitude)
        let boundingRect = bodyString.boundingRect(with: bodyRect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        bodyString.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: boundingRect.height))
        y += boundingRect.height + 4

        // Tags badge
        let tagNames = note.tags.map { TagHelper.tagName($0) }.joined(separator: ", ")
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

    // MARK: - macOS Helpers

    #if canImport(AppKit)
    private func buildReportText(
        student: Student,
        notes: [Note],
        style: ReportStyle,
        dateRange: ClosedRange<Date>
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Title
        let title = "\(student.firstName) - \(style.rawValue)\n\n"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ]
        result.append(NSAttributedString(string: title, attributes: titleAttrs))

        // Date range
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateRangeText = "\(dateFormatter.string(from: dateRange.lowerBound)) - \(dateFormatter.string(from: dateRange.upperBound))\n\n"
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        result.append(NSAttributedString(string: dateRangeText, attributes: dateAttrs))

        // Divider
        result.append(NSAttributedString(string: "─────────────────────────────────────\n\n"))

        // Notes
        let groupedNotes: [(String, [Note])]
        if style.groupsByCategory {
            groupedNotes = groupNotesByCategory(notes)
        } else {
            groupedNotes = [("Notes", notes)]
        }

        for (categoryName, categoryNotes) in groupedNotes {
            if style.groupsByCategory && categoryNotes.count > 0 {
                let categoryAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: NSColor.labelColor
                ]
                result.append(NSAttributedString(string: "\(categoryName)\n", attributes: categoryAttrs))
            }

            for note in categoryNotes {
                // Date
                let noteDateFormatter = DateFormatter()
                noteDateFormatter.dateStyle = .short
                noteDateFormatter.timeStyle = .short
                let noteDateAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
                result.append(NSAttributedString(string: "\(noteDateFormatter.string(from: note.createdAt))\n", attributes: noteDateAttrs))

                // Body
                let bodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.labelColor
                ]
                result.append(NSAttributedString(string: "\(note.body)\n", attributes: bodyAttrs))

                // Category
                let categoryAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: NSColor.systemBlue
                ]
                let noteTagNames = note.tags.map { TagHelper.tagName($0) }.joined(separator: ", ")
                let tagLabel = noteTagNames.isEmpty ? "General" : noteTagNames
                result.append(NSAttributedString(string: "[\(tagLabel)]\n\n", attributes: categoryAttrs))
            }
        }

        // Footer
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        result.append(NSAttributedString(string: "\n\nGenerated by Maria's Notebook", attributes: footerAttrs))

        return result
    }

    private func createPDFPage(from attributedString: NSAttributedString, pageSize: NSSize, margin: CGFloat) -> PDFPage? {
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

    // MARK: - Common Helpers

    private func groupNotesByCategory(_ notes: [Note]) -> [(String, [Note])] {
        // Group notes by their first tag (or "General" if untagged)
        var grouped: [String: [Note]] = [:]
        for note in notes {
            if let firstTag = note.tags.first {
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
