import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StudentsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var students: [Student]

    @State private var showingAddStudent: Bool = false
    @State private var showingStudentCSVImporter: Bool = false
    @State private var importAlert: ImportAlert? = nil

    @State private var mappingHeaders: [String] = []
    @State private var pendingMapping: StudentCSVImporter.Mapping? = nil
    @State private var pendingFileURL: URL? = nil
    @State private var pendingParsedImport: StudentCSVImporter.Parsed? = nil
    @State private var showingMappingSheet: Bool = false

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        StudentsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Button {
                    showingAddStudent = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: AppTheme.FontSize.titleXLarge))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        showingStudentCSVImporter = true
                    } label: {
                        Label("Import Students from CSV…", systemImage: "arrow.down.doc")
                    }
                }
                .padding()
            }
            .sheet(isPresented: $showingAddStudent) {
                AddStudentView()
            }
            .fileImporter(
                isPresented: $showingStudentCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                do {
                    let url = try result.get()

                    Task.detached(priority: .userInitiated) {
                        let needsAccess = url.startAccessingSecurityScopedResource()
                        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                        do {
                            let data = try Data(contentsOf: url)
                            let csvOpt = await MainActor.run { CSVParser.parse(data: data) }
                            guard let csv = csvOpt else {
                                await MainActor.run {
                                    importAlert = ImportAlert(title: "Import Failed", message: "Unsupported text encoding; please use UTF-8.")
                                }
                                return
                            }
                            await MainActor.run {
                                self.pendingFileURL = url
                                self.mappingHeaders = csv.headers
                                self.pendingMapping = StudentCSVImporter.detectMapping(headers: csv.headers)
                                self.showingMappingSheet = true
                            }
                        } catch {
                            await MainActor.run {
                                importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                            }
                        }
                    }
                } catch {
                    importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                }
            }
            .sheet(isPresented: $showingMappingSheet) {
                StudentCSVMappingView(headers: mappingHeaders, onCancel: {
                    showingMappingSheet = false
                    pendingFileURL = nil
                }, onConfirm: { mapping in
                    // Ensure we have a file URL before starting the background work
                    guard let fileURL = pendingFileURL else { return }
                    Task.detached(priority: .userInitiated) {
                        let needsAccess = fileURL.startAccessingSecurityScopedResource()
                        defer { if needsAccess { fileURL.stopAccessingSecurityScopedResource() } }
                        do {
                            let data = try Data(contentsOf: fileURL)
                            let parsed: StudentCSVImporter.Parsed = try await MainActor.run {
                                try StudentCSVImporter.parse(data: data, mapping: mapping, existingStudents: self.students)
                            }
                            await MainActor.run {
                                pendingParsedImport = parsed
                                showingMappingSheet = false
                            }
                        } catch {
                            await MainActor.run {
                                importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                                showingMappingSheet = false
                            }
                        }
                    }
                })
            }
            .sheet(item: $pendingParsedImport, onDismiss: {
                pendingFileURL = nil
            }) { parsed in
                StudentImportPreviewView(parsed: parsed, onCancel: {
                    pendingParsedImport = nil
                }, onConfirm: { filtered in
                    do {
                        let summary = try StudentCSVImporter.commit(parsed: filtered, into: modelContext, existingStudents: students)
                        var message = "Imported \(summary.insertedCount) new and updated \(summary.updatedCount) existing student(s)."
                        if summary.potentialDuplicates.count > 0 {
                            let firstFew = summary.potentialDuplicates.prefix(5).joined(separator: "\n• ")
                            message += "\n\nPotential duplicates detected: \(summary.potentialDuplicates.count)."
                            if !firstFew.isEmpty { message += "\n\nExamples:\n• \(firstFew)" }
                        }
                        if !summary.warnings.isEmpty {
                            message += "\n\nWarnings:\n" + summary.warnings.joined(separator: "\n")
                        }
                        importAlert = ImportAlert(title: "CSV Import Complete", message: message)
                    } catch {
                        importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                    }
                    pendingParsedImport = nil
                })
                .frame(minWidth: 620, minHeight: 520)
            }
            .alert(item: $importAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
    }
}
