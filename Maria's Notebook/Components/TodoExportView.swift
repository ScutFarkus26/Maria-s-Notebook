import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct TodoExportView: View {
    private static let logger = Logger.todos
    @Environment(\.dismiss) private var dismiss
    let todos: [TodoItem]
    
    @State private var selectedFormat: TodoExportService.ExportFormat = .text
    @State private var exportedContent: String = ""
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showCopiedAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Format selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export Format")
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        FormatOption(
                            format: .text,
                            title: "Plain Text",
                            description: "Simple text format, easy to read",
                            icon: "doc.text",
                            isSelected: selectedFormat == .text
                        ) {
                            selectedFormat = .text
                            generateExport()
                        }
                        
                        FormatOption(
                            format: .markdown,
                            title: "Markdown",
                            description: "Formatted text with sections and styling",
                            icon: "doc.richtext",
                            isSelected: selectedFormat == .markdown
                        ) {
                            selectedFormat = .markdown
                            generateExport()
                        }
                        
                        FormatOption(
                            format: .csv,
                            title: "CSV",
                            description: "Spreadsheet format for Excel/Numbers",
                            icon: "tablecells",
                            isSelected: selectedFormat == .csv
                        ) {
                            selectedFormat = .csv
                            generateExport()
                        }
                        
                        FormatOption(
                            format: .json,
                            title: "JSON",
                            description: "Structured data format for developers",
                            icon: "curlybraces",
                            isSelected: selectedFormat == .json
                        ) {
                            selectedFormat = .json
                            generateExport()
                        }
                    }
                }
                .padding()
                
                Divider()
                
                // Preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview")
                        .font(.headline)
                    
                    ScrollView {
                        Text(exportedContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(8)
                    }
                }
                .padding()
                
                Divider()
                
                // Actions
                HStack(spacing: 12) {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        shareExport()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Export Todos")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                generateExport()
            }
            .alert("Copied!", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Export content copied to clipboard")
            }
            #if os(iOS)
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            #endif
        }
    }
    
    private func generateExport() {
        switch selectedFormat {
        case .text:
            exportedContent = TodoExportService.exportAsText(todos: todos)
        case .csv:
            exportedContent = TodoExportService.exportAsCSV(todos: todos)
        case .markdown:
            exportedContent = TodoExportService.exportAsMarkdown(todos: todos)
        case .json:
            exportedContent = TodoExportService.exportAsJSON(todos: todos) ?? "Error generating JSON"
        }
    }
    
    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportedContent, forType: .string)
        #else
        UIPasteboard.general.string = exportedContent
        #endif
        showCopiedAlert = true
    }
    
    private func shareExport() {
        let filename = "todos_export_\(Date().timeIntervalSince1970)"
        guard let url = TodoExportService.saveToFile(
            content: exportedContent, filename: filename, format: selectedFormat
        ) else {
            return
        }
        
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "\(filename).\(fileExtension)"
        savePanel.allowedContentTypes = [contentType]
        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                do {
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                } catch {
                    Self.logger.error("[\(#function)] Failed to save export file: \(error)")
                }
            }
        }
        #else
        shareURL = url
        showShareSheet = true
        #endif
    }
    
    private var fileExtension: String {
        switch selectedFormat {
        case .text: return "txt"
        case .csv: return "csv"
        case .markdown: return "md"
        case .json: return "json"
        }
    }
    
    private var contentType: UTType {
        switch selectedFormat {
        case .text: return .plainText
        case .csv: return .commaSeparatedText
        case .markdown: return .plainText
        case .json: return .json
        }
    }
}

// MARK: - Format Option

private struct FormatOption: View {
    let format: TodoExportService.ExportFormat
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - iOS Share Sheet

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
