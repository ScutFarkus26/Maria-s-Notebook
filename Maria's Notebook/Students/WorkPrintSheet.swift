// WorkPrintSheet.swift
// Sheet wrapper for presenting the print interface

import SwiftUI

#if os(macOS)
import AppKit
import PDFKit
#endif

/// Sheet wrapper for presenting the print interface
struct WorkPrintSheet: View {
    let workItems: [WorkModel]
    let students: [Student]
    let lessons: [Lesson]
    let filterDescription: String
    let sortDescription: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        VStack(spacing: 0) {
            // Preview the print view
            ScrollView {
                WorkPrintView(
                    workItems: workItems,
                    students: students,
                    lessons: lessons,
                    filterDescription: filterDescription,
                    sortDescription: sortDescription
                )
                .frame(width: 612 * 0.5, height: 792 * 0.5) // 50% scale for preview
                .scaleEffect(0.5)
                .frame(width: 612 * 0.5, height: 792 * 0.5)
            }
            .background(Color.gray.opacity(0.1))

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Print", systemImage: "printer") {
                    presentPrint()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        #else
        VStack(spacing: 16) {
            HStack {
                Text("Print Preview")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }

            ScrollView {
                WorkPrintView(
                    workItems: workItems,
                    students: students,
                    lessons: lessons,
                    filterDescription: filterDescription,
                    sortDescription: sortDescription
                )
                .frame(width: 612 * 0.6, height: 792 * 0.6)
                .scaleEffect(0.6)
                .frame(width: 612 * 0.6, height: 792 * 0.6)
            }
            .background(Color.gray.opacity(0.1))

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Print", systemImage: "printer") {
                    presentPrint()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 700)
        #endif
    }

    private func presentPrint() {
        #if os(iOS)
        let printView = WorkPrintView(
            workItems: workItems,
            students: students,
            lessons: lessons,
            filterDescription: filterDescription,
            sortDescription: sortDescription
        )

        if let pdfData = PDFRenderer.render(view: printView, size: CGSize(width: 612, height: 792)) {
            let printController = UIPrintInteractionController.shared
            printController.printingItem = pdfData

            let printInfo = UIPrintInfo.printInfo()
            printInfo.outputType = .general
            printInfo.jobName = "Open Work Report"
            printController.printInfo = printInfo

            printController.present(animated: true) { _, completed, _ in
                if completed {
                    dismiss()
                }
            }
        }
        #else
        let printableWidth: CGFloat = 612 - 72

        let printView = WorkPrintView(
            workItems: workItems,
            students: students,
            lessons: lessons,
            filterDescription: filterDescription,
            sortDescription: sortDescription
        )

        guard let pdfData = renderSheetViewToPDF(printView, width: printableWidth) else {
            dismiss()
            return
        }

        guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else { return }
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        if let doc = PDFDocument(data: pdfData),
           let keyWindow = NSApp.keyWindow,
           let operation = doc.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: false) {
            operation.showsPrintPanel = true
            operation.runModal(for: keyWindow, delegate: nil, didRun: nil, contextInfo: nil)
        }
        dismiss()
        #endif
    }

    #if os(macOS)
    private func renderSheetViewToPDF<V: View>(_ view: V, width: CGFloat) -> Data? {
        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: .aqua)

        let tempWindow = NSWindow(
            contentRect: NSRect(x: TimeoutConstants.offscreenCoordinate, y: TimeoutConstants.offscreenCoordinate, width: width, height: 2000),
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
    #endif
}
