// ReportGeneratorView.swift
// View for generating PDF reports from flagged notes

import SwiftUI
import SwiftData

struct ReportGeneratorView: View {
    let student: Student
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDateRange: ReportGeneratorService.DateRangeOption = .lastMonth
    @State private var selectedStyle: ReportGeneratorService.ReportStyle = .progressReport
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()

    @State private var isGenerating: Bool = false
    @State private var generatedPDF: Data?
    @State private var noteCount: Int = 0
    @State private var showingShareSheet: Bool = false
    @State private var showingPreview: Bool = false
    @State private var errorMessage: String?

    private let reportService = ReportGeneratorService()

    private var effectiveDateRange: ClosedRange<Date> {
        if selectedDateRange == .custom {
            return customStartDate...customEndDate
        }
        return selectedDateRange.dateRange()
    }

    var body: some View {
        NavigationStack {
            Form {
                // Date Range Section
                Section {
                    Picker("Period", selection: $selectedDateRange) {
                        ForEach(ReportGeneratorService.DateRangeOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    if selectedDateRange == .custom {
                        DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Date Range")
                } footer: {
                    Text("Only notes flagged for report within this range will be included.")
                }

                // Report Style Section
                Section {
                    Picker("Style", selection: $selectedStyle) {
                        ForEach(ReportGeneratorService.ReportStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                } header: {
                    Text("Report Style")
                } footer: {
                    styleDescription
                }

                // Preview Section
                Section {
                    Button {
                        fetchNoteCount()
                    } label: {
                        HStack {
                            Text("Check Available Notes")
                            Spacer()
                            if noteCount > 0 {
                                Text("\(noteCount) notes")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Preview")
                }

                // Generate Section
                Section {
                    Button {
                        generateReport()
                    } label: {
                        HStack {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isGenerating ? "Generating..." : "Generate Report")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isGenerating || noteCount == 0)

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // Share Section (after generation)
                if generatedPDF != nil {
                    Section {
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Share Report", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showingPreview = true
                        } label: {
                            Label("Preview Report", systemImage: "doc.text.magnifyingglass")
                        }
                    } header: {
                        Text("Export")
                    }
                }
            }
            .navigationTitle("Generate Report")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchNoteCount()
            }
            .onChange(of: selectedDateRange) { _, _ in
                fetchNoteCount()
            }
            .onChange(of: customStartDate) { _, _ in
                if selectedDateRange == .custom {
                    fetchNoteCount()
                }
            }
            .onChange(of: customEndDate) { _, _ in
                if selectedDateRange == .custom {
                    fetchNoteCount()
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingShareSheet) {
                if let pdfData = generatedPDF {
                    ShareSheet(items: [pdfData])
                }
            }
            #endif
            .sheet(isPresented: $showingPreview) {
                if let pdfData = generatedPDF {
                    PDFPreviewView(pdfData: pdfData, studentName: student.firstName)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 500)
        #endif
    }

    private var styleDescription: some View {
        Group {
            switch selectedStyle {
            case .progressReport:
                Text("Groups notes by category with images. Best for regular progress updates.")
            case .parentConference:
                Text("Chronological list with images. Ideal for parent meetings.")
            case .iepDocumentation:
                Text("Groups by category without images. Focused documentation format.")
            }
        }
    }

    private func fetchNoteCount() {
        let notes = reportService.fetchReportNotes(
            for: student,
            dateRange: effectiveDateRange,
            context: modelContext
        )
        noteCount = notes.count
    }

    private func generateReport() {
        isGenerating = true
        errorMessage = nil
        generatedPDF = nil

        Task {
            let notes = reportService.fetchReportNotes(
                for: student,
                dateRange: effectiveDateRange,
                context: modelContext
            )

            if notes.isEmpty {
                await MainActor.run {
                    errorMessage = "No flagged notes found in the selected date range."
                    isGenerating = false
                }
                return
            }

            let pdfData = reportService.generatePDF(
                student: student,
                notes: notes,
                style: selectedStyle,
                dateRange: effectiveDateRange
            )

            await MainActor.run {
                if pdfData.isEmpty {
                    errorMessage = "Failed to generate PDF. Please try again."
                } else {
                    generatedPDF = pdfData
                }
                isGenerating = false
            }
        }
    }
}

// MARK: - Share Sheet (iOS)

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - PDF Preview View

struct PDFPreviewView: View {
    let pdfData: Data
    let studentName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(data: pdfData)
                .navigationTitle("\(studentName) Report")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 700)
        #endif
    }
}

// MARK: - PDFKit SwiftUI Wrapper

import PDFKit

#if os(iOS)
struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
    }
}
#elseif os(macOS)
struct PDFKitView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Skip if data hasn't changed (compare by hash to avoid redundant updates)
        let newHash = data.hashValue
        if context.coordinator.lastDataHash == newHash { return }
        context.coordinator.lastDataHash = newHash

        // Defer document assignment to next run loop to avoid layout recursion
        guard let document = PDFDocument(data: data) else { return }
        DispatchQueue.main.async {
            pdfView.document = document
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var lastDataHash: Int?
    }
}
#endif

// MARK: - Preview

#Preview {
    @Previewable @State var student = Student(firstName: "Test", lastName: "Student", birthday: Date(), level: .lower)
    ReportGeneratorView(student: student)
        .previewEnvironment()
}
