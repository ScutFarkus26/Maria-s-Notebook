// WorkPrintView+PDFRendering.swift
// PDF rendering logic for iOS and macOS print support

import SwiftUI

#if os(iOS)
import UIKit

/// Helper to render SwiftUI views to PDF on iOS
@MainActor
struct PDFRenderer {
    static func render<Content: View>(view: Content, size: CGSize) -> Data? {
        let hostingController = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        hostingController.view.bounds = CGRect(origin: .zero, size: size)
        hostingController.view.backgroundColor = .white

        // CRITICAL: The hosting controller's view must be in the view hierarchy for SwiftUI to render.
        // Add it to a temporary window using the active window scene.
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
              ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else { return nil }
        let tempWindow = UIWindow(windowScene: windowScene)
        tempWindow.frame = CGRect(
            x: TimeoutConstants.offscreenCoordinate,
            y: TimeoutConstants.offscreenCoordinate,
            width: size.width,
            height: size.height
        )
        tempWindow.rootViewController = hostingController
        tempWindow.isHidden = false
        tempWindow.layoutIfNeeded()

        // Force layout and give SwiftUI time to render
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        // Allow the run loop to process pending layout
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        let data = pdfRenderer.pdfData { context in
            context.beginPage()
            hostingController.view.layer.render(in: context.cgContext)
        }

        // Clean up: remove from window hierarchy
        tempWindow.isHidden = true
        tempWindow.rootViewController = nil

        return data
    }
}
#endif

#if os(macOS)
import AppKit
import PDFKit

/// macOS-specific print controller
struct WorkPrintController: NSViewRepresentable {
    let workItems: [WorkModel]
    let students: [Student]
    let lessons: [Lesson]
    let filterDescription: String
    let sortDescription: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        Task { @MainActor in
            self.printContent()
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func printContent() {
        let printableWidth: CGFloat = 612 - 72 // Page width minus margins

        let printView = WorkPrintView(
            workItems: workItems,
            students: students,
            lessons: lessons,
            filterDescription: filterDescription,
            sortDescription: sortDescription
        )

        guard let pdfData = renderViewToPDF(printView, width: printableWidth) else { return }

        guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else { return }
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.jobDisposition = .preview

        if let doc = PDFDocument(data: pdfData),
           let operation = doc.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: false) {
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            operation.run()
        }
    }

    // swiftlint:disable:next function_body_length
    private func renderViewToPDF<V: View>(_ view: V, width: CGFloat) -> Data? {
        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: .aqua)

        let tempWindow = NSWindow(
            contentRect: NSRect(
                x: TimeoutConstants.offscreenCoordinate,
                y: TimeoutConstants.offscreenCoordinate,
                width: width, height: 2000
            ),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        tempWindow.contentView = hostingView
        tempWindow.backgroundColor = .white
        tempWindow.makeKeyAndOrderFront(nil)

        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 2000)
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        let fittingSize = hostingView.fittingSize
        let finalHeight = max(fittingSize.height, 100)
        let finalSize = NSSize(width: width, height: finalHeight)

        hostingView.setFrameSize(finalSize)
        tempWindow.setContentSize(finalSize)
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        let image = NSImage(size: finalSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: finalSize).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            hostingView.layer?.render(in: context)
        }
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            tempWindow.orderOut(nil)
            return nil
        }

        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: finalSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            tempWindow.orderOut(nil)
            return nil
        }

        pdfContext.beginPDFPage(nil)
        pdfContext.draw(cgImage, in: mediaBox)
        pdfContext.endPDFPage()
        pdfContext.closePDF()

        tempWindow.orderOut(nil)
        return pdfData as Data
    }
}
#endif
