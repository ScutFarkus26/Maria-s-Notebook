//
//  WorkPDFRenderer.swift
//  Maria's Notebook
//
//  PDF rendering service for Work Agenda view
//

import Foundation
#if os(macOS)
import AppKit
import PDFKit

enum WorkPDFRenderer {
    struct PrintItem: Identifiable {
        let id: UUID
        let lessonTitle: String
        let studentName: String
        let statusLabel: String
        let ageDays: Int
        let dueAt: Date?
        let needsAttention: Bool
    }

    static func renderPDF(
        items: [PrintItem],
        sortMode: WorkAgendaSortMode,
        searchText: String
    ) -> Data? {
        // Page setup
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 36
        let contentWidth = pageWidth - (margin * 2)

        // Fonts
        let titleFont = NSFont.boldSystemFont(ofSize: 14)
        let headerFont = NSFont.boldSystemFont(ofSize: 10)
        let bodyFont = NSFont.systemFont(ofSize: 9)
        let smallFont = NSFont.systemFont(ofSize: 8)

        // Colors
        let blackColor = NSColor.black
        let grayColor = NSColor(white: 0.35, alpha: 1.0)
        let lightGrayColor = NSColor(white: 0.6, alpha: 1.0)

        // Group and sort
        let (_, groups, groupOrder) = groupItems(items, by: sortMode)

        // Create PDF
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        // Start first page
        context.beginPDFPage(nil)
        var yPosition = pageHeight - margin

        // Header
        yPosition -= drawText(
            "Open Work", at: CGPoint(x: margin, y: yPosition),
            font: titleFont, color: blackColor,
            maxWidth: contentWidth, in: context
        )

        // Metadata
        var metaText = "\(dateFormatter.string(from: Date())) • \(sortMode.rawValue) • \(items.count) items"
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            metaText += " • Filter: \(searchText)"
        }
        yPosition -= drawText(
            metaText, at: CGPoint(x: margin, y: yPosition),
            font: smallFont, color: grayColor,
            maxWidth: contentWidth, in: context
        )
        yPosition -= 8

        // Separator
        drawLine(
            from: CGPoint(x: margin, y: yPosition),
            to: CGPoint(x: pageWidth - margin, y: yPosition),
            color: lightGrayColor, in: context
        )
        yPosition -= 6

        // Draw groups
        for groupName in groupOrder {
            guard let groupItems = groups[groupName] else { continue }

            // New page if needed
            if yPosition < margin + 30 {
                context.endPDFPage()
                context.beginPDFPage(nil)
                yPosition = pageHeight - margin
            }

            // Group header
            let headerHeight: CGFloat = 12
            context.setFillColor(NSColor(white: 0.92, alpha: 1.0).cgColor)
            context.fill(CGRect(x: margin, y: yPosition - headerHeight, width: contentWidth, height: headerHeight))

            drawSingleLine(
                "\(groupName) (\(groupItems.count))",
                at: CGPoint(x: margin + 4, y: yPosition - headerHeight + 3),
                font: headerFont, color: blackColor, in: context
            )
            yPosition -= headerHeight + 2

            // Items
            for item in groupItems {
                if yPosition < margin + 14 {
                    context.endPDFPage()
                    context.beginPDFPage(nil)
                    yPosition = pageHeight - margin
                }

                let itemText = buildItemText(item, sortMode: sortMode)
                let detailsText = buildDetailsText(item, dateFormatter: dateFormatter)

                drawSingleLine(
                    itemText, at: CGPoint(x: margin + 6, y: yPosition - 9),
                    font: bodyFont, color: blackColor, in: context
                )

                // Right-align details
                let detailsAttr: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: grayColor]
                let detailsSize = (detailsText as NSString).size(withAttributes: detailsAttr)
                drawSingleLine(
                    detailsText,
                    at: CGPoint(
                        x: pageWidth - margin - detailsSize.width,
                        y: yPosition - 9
                    ),
                    font: smallFont, color: grayColor, in: context
                )

                yPosition -= 12
            }

            yPosition -= 4
        }

        if items.isEmpty {
            yPosition -= drawText(
                "No open work items.",
                at: CGPoint(x: margin, y: yPosition),
                font: bodyFont, color: grayColor,
                maxWidth: contentWidth, in: context
            )
        }

        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    // MARK: - Helpers

    private static func groupItems(
        _ items: [PrintItem],
        by sortMode: WorkAgendaSortMode
    ) -> ([PrintItem], [String: [PrintItem]], [String]) {
        let sorted = items.sorted { lhs, rhs in
            switch sortMode {
            case .lesson: return lhs.lessonTitle.localizedCaseInsensitiveCompare(rhs.lessonTitle) == .orderedAscending
            case .student: return lhs.studentName.localizedCaseInsensitiveCompare(rhs.studentName) == .orderedAscending
            case .age: return lhs.ageDays > rhs.ageDays
            case .needsAttention:
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
                return lhs.ageDays > rhs.ageDays
            }
        }

        var groupOrder: [String] = []
        var groups: [String: [PrintItem]] = [:]

        for item in sorted {
            let key = groupKey(for: item, sortMode: sortMode)
            if groups[key] == nil {
                groupOrder.append(key)
                groups[key] = []
            }
            groups[key]?.append(item)
        }

        return (sorted, groups, groupOrder)
    }

    private static func groupKey(for item: PrintItem, sortMode: WorkAgendaSortMode) -> String {
        switch sortMode {
        case .lesson: return item.lessonTitle
        case .student: return item.studentName
        case .age:
            let days = item.ageDays
            if days <= 0 {
                return "Today"
            } else if days <= 3 {
                return "1-3 days"
            } else if days <= 7 {
                return "4-7 days"
            } else if days <= 14 {
                return "8-14 days"
            } else if days <= 30 {
                return "15-30 days"
            } else {
                return "30+ days"
            }
        case .needsAttention:
            return item.needsAttention ? "Needs Attention" : "Other"
        }
    }

    private static func buildItemText(_ item: PrintItem, sortMode: WorkAgendaSortMode) -> String {
        var text = "☐ "
        switch sortMode {
        case .lesson: text += item.studentName
        case .student: text += item.lessonTitle
        default: text += "\(item.lessonTitle) — \(item.studentName)"
        }
        return text
    }

    private static func buildDetailsText(_ item: PrintItem, dateFormatter: DateFormatter) -> String {
        var details: [String] = [item.statusLabel, "\(item.ageDays)d"]
        if let due = item.dueAt {
            details.append(dateFormatter.string(from: due))
        }
        if item.needsAttention {
            details.append("⚠")
        }
        return details.joined(separator: " • ")
    }

    private static func drawText(
        _ text: String, at point: CGPoint,
        font: NSFont, color: NSColor,
        maxWidth: CGFloat, in context: CGContext
    ) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: attrString.length),
            nil, CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude), nil
        )

        let path = CGPath(
            rect: CGRect(
                x: point.x, y: point.y - suggestedSize.height,
                width: maxWidth, height: suggestedSize.height + 2
            ), transform: nil
        )
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrString.length), path, nil)
        CTFrameDraw(frame, context)

        return suggestedSize.height
    }

    private static func drawSingleLine(
        _ text: String, at point: CGPoint,
        font: NSFont, color: NSColor,
        in context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func drawLine(from start: CGPoint, to end: CGPoint, color: NSColor, in context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.5)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    static func configuredPrintInfo() -> NSPrintInfo {
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        return printInfo
    }
}
#endif
