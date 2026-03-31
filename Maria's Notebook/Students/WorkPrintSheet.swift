// WorkPrintSheet.swift
// Sheet wrapper for presenting the print interface

import SwiftUI
import CoreData

#if os(macOS)
import AppKit
import PDFKit
#endif

/// Sheet wrapper for presenting the print interface
struct WorkPrintSheet: View {
    let workItems: [CDWorkModel]
    let students: [CDStudent]
    let lessons: [CDLesson]
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
            .background(Color.gray.opacity(UIConstants.OpacityConstants.light))

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
            .background(Color.gray.opacity(UIConstants.OpacityConstants.light))

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

    private var groups: [WorkPrintGroup] {
        WorkPrintView.computeGroups(workItems: workItems, students: students)
    }

    private func presentPrint() {
        #if os(iOS)
        presentPrintiOS()
        #else
        presentPrintMacOS()
        dismiss()
        #endif
    }

    #if os(iOS)
    private func presentPrintiOS() {
        guard let pdfData = PDFRenderer.renderGroupedPDF(
            groups: groups,
            lessons: lessons,
            filterDescription: filterDescription,
            sortDescription: sortDescription,
            workItemCount: workItems.count
        ) else { return }

        let printController = UIPrintInteractionController.shared
        printController.printingItem = pdfData

        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "Open Work Report"
        printController.printInfo = printInfo

        printController.present(animated: true) { _, completed, _ in
            if completed { dismiss() }
        }
    }
    #else
    private func presentPrintMacOS() {
        guard let pdfData = MacPDFRenderer.renderGroupedPDF(
            groups: groups,
            lessons: lessons,
            filterDescription: filterDescription,
            sortDescription: sortDescription,
            workItemCount: workItems.count
        ) else { return }

        guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else { return }
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        if let doc = PDFDocument(data: pdfData),
           let keyWindow = NSApp.keyWindow,
           let operation = doc.printOperation(
            for: printInfo,
            scalingMode: .pageScaleNone,
            autoRotate: false
           ) {
            operation.showsPrintPanel = true
            operation.runModal(for: keyWindow, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }
    #endif
}
