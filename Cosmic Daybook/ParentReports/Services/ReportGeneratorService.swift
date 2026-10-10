// ReportGeneratorService.swift
// Service for generating PDF reports from flagged notes
// swiftlint:disable file_length

import Foundation
import CoreData
import SwiftUI
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

    // MARK: - Report Options

    enum DateRangeOption: String, CaseIterable, Identifiable {
        case lastWeek = "Last 7 Days"
        case lastMonth = "Last 30 Days"
        case lastQuarter = "Last 90 Days"
        case thisSchoolYear = "This School Year"
        case custom = "Custom Range"

        var id: String { rawValue }

        /// The whole days the report covers, from the start of the first day to the
        /// end of the last, so a note written on either end day is never dropped by
        /// the time of day the sheet happened to open (bug hunt 2026-10-10, P2 #36).
        /// "This School Year" starts on the school year's first day as the class set
        /// it (`YearPlanStaleness.currentYearStart`, the synced start the share and
        /// the counters use), never a guessed month count. `.custom` covers
        /// `customStart` through `customEnd`, in either order.
        func dateRange(
            from today: Date = Date(),
            customStart: Date? = nil,
            customEnd: Date? = nil,
            schoolYearStart: (Date) -> Date = { YearPlanStaleness.currentYearStart(asOf: $0) }
        ) -> ClosedRange<Date> {
            let calendar = AppCalendar.shared
            func daysBack(_ days: Int) -> Date {
                calendar.date(byAdding: .day, value: -days, to: today) ?? today
            }
            switch self {
            case .lastWeek:
                return ReportGeneratorService.wholeDays(from: daysBack(7), through: today)
            case .lastMonth:
                return ReportGeneratorService.wholeDays(from: daysBack(30), through: today)
            case .lastQuarter:
                return ReportGeneratorService.wholeDays(from: daysBack(90), through: today)
            case .thisSchoolYear:
                return ReportGeneratorService.wholeDays(from: schoolYearStart(today), through: today)
            case .custom:
                let start = customStart ?? daysBack(30)
                let end = customEnd ?? today
                // Ordered defensively: a ClosedRange with lowerBound > upperBound traps.
                return ReportGeneratorService.wholeDays(from: min(start, end), through: max(start, end))
            }
        }
    }

    /// Where "This School Year" starts, and whether that is known on this device.
    struct SchoolYearStart: Equatable {
        let date: Date
        /// False when neither the class's school-year start nor any of this year's
        /// records has reached this device, so `date` is only the September 1 fallback.
        let isKnown: Bool
    }

    /// The first day "This School Year" covers. With the class's start set on (or
    /// synced to) this device, that start. Without it, `currentYearStart` answers
    /// September 1, which would drop a class that began in late August (2026 began
    /// August 25), so the report starts no later than the class's first attendance
    /// mark since August 1, or failing that its earliest note or given lesson since
    /// then. With none of those either, the start is unknown and the sheet says so.
    static func schoolYearStart(
        asOf today: Date,
        context: NSManagedObjectContext,
        hasConfiguredStart: Bool = YearPlanStaleness.hasConfiguredStart
    ) -> SchoolYearStart {
        let fallback = YearPlanStaleness.currentYearStart(asOf: today)
        guard !hasConfiguredStart else { return SchoolYearStart(date: fallback, isKnown: true) }

        let calendar = AppCalendar.shared
        let year = calendar.component(.year, from: fallback)
        guard let augustFirst = calendar.date(from: DateComponents(year: year, month: 8, day: 1)) else {
            return SchoolYearStart(date: fallback, isKnown: false)
        }
        let window = (augustFirst as NSDate, AppCalendar.dayRange(for: today).end as NSDate)

        func earliest<T: NSManagedObject>(_ type: T.Type, _ key: String, extra: String = "") -> Date? {
            let request = CDFetchRequest(T.self)
            request.predicate = NSPredicate(format: "\(key) >= %@ AND \(key) < %@\(extra)", window.0, window.1)
            request.sortDescriptors = [NSSortDescriptor(key: key, ascending: true)]
            request.fetchLimit = 1
            return context.safeFetch(request).first?.value(forKey: key) as? Date
        }

        let firstMark = earliest(
            CDAttendanceRecord.self, "date", extra: " AND statusRaw != '\(AttendanceStatus.unmarked.rawValue)'"
        )
        let evidence = firstMark ?? [
            earliest(CDNote.self, "createdAt"),
            earliest(CDLessonAssignment.self, "presentedAt")
        ].compactMap { $0 }.min()
        guard let evidence else { return SchoolYearStart(date: fallback, isKnown: false) }
        return SchoolYearStart(date: min(fallback, evidence), isKnown: true)
    }

    /// From the start of `first`'s day to the last instant of `last`'s day.
    static func wholeDays(from first: Date, through last: Date) -> ClosedRange<Date> {
        let start = AppCalendar.startOfDay(first)
        let end = AppCalendar.dayRange(for: last).end.addingTimeInterval(-0.001)
        return start...max(start, end)
    }

    enum ReportStyle: String, CaseIterable, Identifiable {
        case progressReport = "Progress Report"
        case parentConference = "Parent Conference"
        case iepDocumentation = "IEP Documentation"

        var id: String { rawValue }

        var groupsByCategory: Bool {
            switch self {
            case .progressReport: return true
            case .parentConference: return false
            case .iepDocumentation: return true
            }
        }
    }

    // MARK: - Generate PDF

    /// The report as a US Letter PDF: the header, the overview figures, the optional
    /// summary and the notes, flowed across as many pages as they need.
    ///
    /// Both platforms build one attributed text and lay it out with TextKit 1, one
    /// `NSTextContainer` per page, so a long note carries on to the next page instead
    /// of running off the bottom (bug hunt 2026-10-10, P2 #32: iOS used to break pages
    /// only between notes). The text is set in fixed ink colors and drawn inside a
    /// light appearance, so a report made in Dark Mode isn't white on white (P2 #31).
    func generatePDF(
        student: CDStudent,
        notes: [CDNote],
        style: ReportStyle,
        dateRange: ClosedRange<Date>,
        aiNarrative: String? = nil
    ) -> Data {
        let reportText = buildReportText(
            student: student,
            notes: notes,
            style: style,
            dateRange: dateRange,
            aiNarrative: aiNarrative
        )
        return renderPDF(reportText, layout: PageLayout())
    }
}

// MARK: - Report Text (both platforms)

extension ReportGeneratorService {
    /// US Letter with 50 pt margins; the footer sits in the bottom margin.
    struct PageLayout {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 50

        var pageRect: CGRect { CGRect(origin: .zero, size: pageSize) }
        var contentSize: CGSize {
            CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        }
        var textOrigin: CGPoint { CGPoint(x: margin, y: margin) }
    }

    /// The colors a report is printed in. A report is paper for a family, so it never
    /// follows the screen's appearance: the system label colors resolve to white in a
    /// dark trait collection, and Apple documents nothing about how a PDF renderer
    /// resolves them, so these are fixed.
    enum ReportInk {
        static var text: PlatformColor { gray(0.0) }
        static var secondary: PlatformColor { gray(0.38) }
        static var rule: PlatformColor { gray(0.7) }
        static var tag: PlatformColor {
            #if canImport(UIKit)
            UIColor(red: 0.0, green: 0.36, blue: 0.75, alpha: 1)
            #else
            NSColor(srgbRed: 0.0, green: 0.36, blue: 0.75, alpha: 1)
            #endif
        }

        private static func gray(_ white: CGFloat) -> PlatformColor {
            #if canImport(UIKit)
            UIColor(white: white, alpha: 1)
            #else
            NSColor(white: white, alpha: 1)
            #endif
        }
    }

    private static func attributes(
        size: CGFloat, bold: Bool = false, color: PlatformColor = ReportInk.text
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: bold ? PlatformFont.boldSystemFont(ofSize: size) : PlatformFont.systemFont(ofSize: size),
            .foregroundColor: color
        ]
    }

    private static let divider = "─────────────────────────────────────\n\n"

    func buildReportText(
        student: CDStudent,
        notes: [CDNote],
        style: ReportStyle,
        dateRange: ClosedRange<Date>,
        aiNarrative: String?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: "\(student.firstName) - \(style.rawValue)\n\n", attributes: Self.attributes(size: 18, bold: true)
        ))
        let rangeStart = DateFormatters.mediumDate.string(from: dateRange.lowerBound)
        let rangeEnd = DateFormatters.mediumDate.string(from: dateRange.upperBound)
        result.append(NSAttributedString(
            string: "\(rangeStart) - \(rangeEnd)\n\n",
            attributes: Self.attributes(size: 12, color: ReportInk.secondary)
        ))
        result.append(NSAttributedString(
            string: Self.divider, attributes: Self.attributes(size: 12, color: ReportInk.rule)
        ))
        if let narrative = aiNarrative {
            appendNarrativeText(to: result, narrative: narrative)
        }
        appendGroupedNotesText(to: result, notes: notes, style: style)
        return result
    }

    private func appendGroupedNotesText(to result: NSMutableAttributedString, notes: [CDNote], style: ReportStyle) {
        let groupedNotes: [(String, [CDNote])] = style.groupsByCategory
            ? groupNotesByCategory(notes)
            : [("Notes", notes)]
        for (categoryName, categoryNotes) in groupedNotes {
            if style.groupsByCategory && !categoryNotes.isEmpty {
                result.append(NSAttributedString(
                    string: "\(categoryName)\n", attributes: Self.attributes(size: 14, bold: true)
                ))
            }
            for note in categoryNotes {
                let dateText = DateFormatters.shortDateTime.string(from: note.createdAt ?? Date())
                result.append(NSAttributedString(
                    string: "\(dateText)\n", attributes: Self.attributes(size: 10, color: ReportInk.secondary)
                ))
                result.append(NSAttributedString(string: "\(note.body)\n", attributes: Self.attributes(size: 11)))
                let tagLabel = note.tagsArray.map { TagHelper.tagName($0) }.joined(separator: ", ")
                result.append(NSAttributedString(
                    string: "[\(tagLabel.isEmpty ? "General" : tagLabel)]\n\n",
                    attributes: Self.attributes(size: 9, color: ReportInk.tag)
                ))
            }
        }
    }

    private func appendNarrativeText(to result: NSMutableAttributedString, narrative: String) {
        result.append(NSAttributedString(string: "Summary\n", attributes: Self.attributes(size: 13, bold: true)))
        result.append(NSAttributedString(string: "\(narrative)\n\n", attributes: Self.attributes(size: 11)))
        result.append(NSAttributedString(
            string: Self.divider, attributes: Self.attributes(size: 12, color: ReportInk.rule)
        ))
    }
}

// MARK: - Pagination and Drawing

extension ReportGeneratorService {
    /// The report text laid out page by page: TextKit 1 with one `NSTextContainer`
    /// per page (TextKit 2's layout manager has a single container). Holds the text
    /// storage, which the layout manager references only weakly.
    struct PaginatedText {
        let storage: NSTextStorage
        let layoutManager: NSLayoutManager
        /// Each page's glyphs, in order. Always at least one page.
        let pages: [NSRange]

        init(_ text: NSAttributedString, contentSize: CGSize) {
            storage = NSTextStorage(attributedString: text)
            layoutManager = NSLayoutManager()
            storage.addLayoutManager(layoutManager)

            var pages: [NSRange] = []
            var laidOut = 0
            repeat {
                let container = NSTextContainer(size: contentSize)
                container.lineFragmentPadding = 0
                layoutManager.addTextContainer(container)
                let range = layoutManager.glyphRange(for: container)
                pages.append(range)
                // A page that took no glyphs can make no progress (an empty
                // report, or a container too small for one line): stop.
                guard range.length > 0 else { break }
                laidOut = NSMaxRange(range)
            } while laidOut < layoutManager.numberOfGlyphs
            self.pages = pages
        }
    }

    private func footerText(page: Int, of pageCount: Int) -> NSAttributedString {
        let text = pageCount > 1
            ? "Generated by Cosmic Daybook · Page \(page) of \(pageCount)"
            : "Generated by Cosmic Daybook"
        return NSAttributedString(string: text, attributes: Self.attributes(size: 8, color: ReportInk.secondary))
    }

    /// Draws one page's text and footer into the current graphics context, which
    /// is top-down (UIKit's, or a flipped AppKit context).
    private func drawPage(_ index: Int, of text: PaginatedText, layout: PageLayout) {
        let range = text.pages[index]
        text.layoutManager.drawBackground(forGlyphRange: range, at: layout.textOrigin)
        text.layoutManager.drawGlyphs(forGlyphRange: range, at: layout.textOrigin)

        let footer = footerText(page: index + 1, of: text.pages.count)
        let size = footer.size()
        let footerY = layout.pageSize.height - layout.margin + (layout.margin - size.height) / 2
        footer.draw(at: CGPoint(x: (layout.pageSize.width - size.width) / 2, y: footerY))
    }

    #if canImport(UIKit)
    func renderPDF(_ reportText: NSAttributedString, layout: PageLayout) -> Data {
        let paginated = PaginatedText(reportText, contentSize: layout.contentSize)
        let renderer = UIGraphicsPDFRenderer(bounds: layout.pageRect, format: UIGraphicsPDFRendererFormat())
        var data = Data()
        // With the fixed ink this changes nothing today; it keeps anything drawn
        // here later from picking up the screen's Dark Mode.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            data = renderer.pdfData { context in
                for index in paginated.pages.indices {
                    context.beginPage()
                    drawPage(index, of: paginated, layout: layout)
                }
            }
        }
        return data
    }
    #elseif canImport(AppKit)
    func renderPDF(_ reportText: NSAttributedString, layout: PageLayout) -> Data {
        let paginated = PaginatedText(reportText, contentSize: layout.contentSize)
        let pdfData = NSMutableData()
        var mediaBox = layout.pageRect
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        let drawPages = {
            for index in paginated.pages.indices {
                context.beginPDFPage(nil)
                context.saveGState()
                // Top-down, as TextKit lays out.
                context.translateBy(x: 0, y: layout.pageSize.height)
                context.scaleBy(x: 1.0, y: -1.0)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                drawPage(index, of: paginated, layout: layout)
                NSGraphicsContext.restoreGraphicsState()
                context.restoreGState()
                context.endPDFPage()
            }
        }
        // As on iOS: whatever isn't fixed ink resolves light, not the window's appearance.
        if let aqua = NSAppearance(named: .aqua) {
            aqua.performAsCurrentDrawingAppearance(drawPages)
        } else {
            drawPages()
        }
        context.closePDF()
        return pdfData as Data
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
