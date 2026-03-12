// WorkPrintView+PDFRendering.swift
// Multi-page PDF rendering with content-aware page breaks.
// Each student section is rendered as an atomic block — sections are never split across pages.

import SwiftUI

// MARK: - Shared Constants

private enum PrintLayout {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter
    static let margin: CGFloat = 36
    static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    static var contentHeight: CGFloat { pageSize.height - margin * 2 }
}

// MARK: - iOS Multi-Page Rendering

#if os(iOS)
import UIKit

/// Renders SwiftUI views to a properly paginated multi-page PDF on iOS.
/// Each student section is kept on a single page — no student is split across pages.
@MainActor
struct PDFRenderer {

    /// A measured and rendered content block.
    private struct Block {
        let image: UIImage
        let height: CGFloat
    }

    // MARK: - Public API

    /// Renders a multi-page PDF from open work data, keeping each student section intact.
    static func renderGroupedPDF(
        groups: [WorkPrintGroup],
        lessons: [Lesson],
        filterDescription: String,
        sortDescription: String,
        workItemCount: Int
    ) -> Data? {
        guard let windowScene = activeWindowScene() else { return nil }

        let width = PrintLayout.contentWidth

        // Build ordered list of content blocks
        var blockViews: [AnyView] = []

        // Header
        blockViews.append(AnyView(
            PrintHeaderContent(
                filterDescription: filterDescription,
                sortDescription: sortDescription,
                workItemCount: workItemCount,
                studentCount: groups.count
            )
        ))

        // Each student section
        for group in groups {
            blockViews.append(AnyView(
                PrintStudentSectionContent(
                    title: group.title,
                    works: group.works,
                    lessons: lessons
                )
            ))
        }

        // Footer
        blockViews.append(AnyView(PrintFooterContent()))

        // Render each block to an image with its measured height
        let blocks = renderBlocks(blockViews, width: width, windowScene: windowScene)

        // Compose blocks onto paginated PDF
        return composePDF(from: blocks)
    }

    // MARK: - Block Rendering

    private static func renderBlocks(
        _ views: [AnyView],
        width: CGFloat,
        windowScene: UIWindowScene
    ) -> [Block] {
        let tempWindow = UIWindow(windowScene: windowScene)
        tempWindow.frame = CGRect(
            x: TimeoutConstants.offscreenCoordinate,
            y: TimeoutConstants.offscreenCoordinate,
            width: width,
            height: 5000
        )
        tempWindow.isHidden = false

        var blocks: [Block] = []

        for view in views {
            let wrapped = view
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.white)

            let hc = UIHostingController(rootView: AnyView(wrapped))
            hc.view.backgroundColor = .white
            tempWindow.rootViewController = hc
            tempWindow.layoutIfNeeded()

            hc.view.setNeedsLayout()
            hc.view.layoutIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

            let fitting = hc.sizeThatFits(
                in: CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            let height = max(fitting.height, 1)

            hc.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            hc.view.setNeedsLayout()
            hc.view.layoutIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: width, height: height)
            )
            let image = renderer.image { ctx in
                hc.view.layer.render(in: ctx.cgContext)
            }

            blocks.append(Block(image: image, height: height))
        }

        tempWindow.isHidden = true
        tempWindow.rootViewController = nil
        return blocks
    }

    // MARK: - PDF Composition

    private static func composePDF(from blocks: [Block]) -> Data {
        let page = PrintLayout.pageSize
        let margin = PrintLayout.margin
        let maxY = page.height - margin

        let pdfRenderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: page)
        )

        return pdfRenderer.pdfData { ctx in
            var cursorY = margin
            var pageOpen = false

            for block in blocks {
                // If block won't fit on current page and we've already placed content, start new page
                if pageOpen && cursorY + block.height > maxY {
                    cursorY = margin
                    pageOpen = false
                }

                // Begin a new page if needed
                if !pageOpen {
                    ctx.beginPage()
                    cursorY = margin
                    pageOpen = true
                }

                // Draw the block image
                let drawRect = CGRect(
                    x: margin, y: cursorY,
                    width: PrintLayout.contentWidth, height: block.height
                )
                block.image.draw(in: drawRect)
                cursorY += block.height
            }
        }
    }

    // MARK: - Helpers

    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }
}
#endif

// MARK: - macOS Multi-Page Rendering

#if os(macOS)
import AppKit
import PDFKit

@MainActor
enum MacPDFRenderer {

    /// A measured and rendered content block.
    private struct Block {
        let image: NSImage
        let height: CGFloat
    }

    // MARK: - Public API

    /// Renders a multi-page PDF from open work data, keeping each student section intact.
    static func renderGroupedPDF(
        groups: [WorkPrintGroup],
        lessons: [Lesson],
        filterDescription: String,
        sortDescription: String,
        workItemCount: Int
    ) -> Data? {
        let width = PrintLayout.contentWidth

        // Build ordered list of content blocks
        var blockViews: [AnyView] = []

        // Header
        blockViews.append(AnyView(
            PrintHeaderContent(
                filterDescription: filterDescription,
                sortDescription: sortDescription,
                workItemCount: workItemCount,
                studentCount: groups.count
            )
        ))

        // Each student section
        for group in groups {
            blockViews.append(AnyView(
                PrintStudentSectionContent(
                    title: group.title,
                    works: group.works,
                    lessons: lessons
                )
            ))
        }

        // Footer
        blockViews.append(AnyView(PrintFooterContent()))

        // Render each block to an image with its measured height
        let blocks = renderBlocks(blockViews, width: width)

        // Compose blocks onto paginated PDF
        return composePDF(from: blocks)
    }

    // MARK: - Block Rendering

    // swiftlint:disable:next function_body_length
    private static func renderBlocks(_ views: [AnyView], width: CGFloat) -> [Block] {
        let tempWindow = NSWindow(
            contentRect: NSRect(
                x: TimeoutConstants.offscreenCoordinate,
                y: TimeoutConstants.offscreenCoordinate,
                width: width, height: 5000
            ),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        tempWindow.backgroundColor = .white
        tempWindow.makeKeyAndOrderFront(nil)

        var blocks: [Block] = []

        for view in views {
            let wrapped = view
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.white)

            let hostingView = NSHostingView(rootView: AnyView(wrapped))
            hostingView.appearance = NSAppearance(named: .aqua)
            tempWindow.contentView = hostingView

            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 5000)
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

            let fittingSize = hostingView.fittingSize
            let height = max(fittingSize.height, 1)

            hostingView.setFrameSize(NSSize(width: width, height: height))
            tempWindow.setContentSize(NSSize(width: width, height: height))
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

            let size = NSSize(width: width, height: height)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            if let ctx = NSGraphicsContext.current?.cgContext {
                hostingView.layer?.render(in: ctx)
            }
            image.unlockFocus()

            blocks.append(Block(image: image, height: height))
        }

        tempWindow.orderOut(nil)
        return blocks
    }

    // MARK: - PDF Composition

    // swiftlint:disable:next function_body_length
    private static func composePDF(from blocks: [Block]) -> Data? {
        let pageWidth = PrintLayout.pageSize.width
        let pageHeight = PrintLayout.pageSize.height
        let margin = PrintLayout.margin
        let contentWidth = PrintLayout.contentWidth
        let maxY = pageHeight - margin

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        // CG coordinate system: origin at bottom-left, y goes up.
        // We track cursorY from the top of the content area downward,
        // then convert to CG coords when drawing.
        var topCursorY: CGFloat = 0 // distance from top of content area
        var pageOpen = false

        for block in blocks {
            // If block won't fit and we've placed content, start a new page
            if pageOpen && margin + topCursorY + block.height > maxY {
                context.endPDFPage()
                topCursorY = 0
                pageOpen = false
            }

            if !pageOpen {
                context.beginPDFPage(nil)
                topCursorY = 0
                pageOpen = true
            }

            // Convert top-down cursor to CG bottom-up coordinates
            let cgY = pageHeight - margin - topCursorY - block.height

            // Draw block image
            if let tiffData = block.image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let cgImage = bitmap.cgImage {
                let drawRect = CGRect(
                    x: margin, y: cgY,
                    width: contentWidth, height: block.height
                )
                context.draw(cgImage, in: drawRect)
            }

            topCursorY += block.height
        }

        if pageOpen {
            context.endPDFPage()
        }
        context.closePDF()

        return pdfData as Data
    }
}
#endif
