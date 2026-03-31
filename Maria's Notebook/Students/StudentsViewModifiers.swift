import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// View modifier for save error alert
struct SaveErrorAlert: ViewModifier {
    @Binding var isPresented: Bool
    let message: String

    func body(content: Content) -> some View {
        content
            .alert("Save Failed", isPresented: $isPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

/// View modifier for CSV import sheets and file importer
struct CSVImportSheets: ViewModifier {
    @Binding var showingImporter: Bool
    @Binding var showingMappingSheet: Bool
    let mappingHeaders: [String]
    @Binding var pendingParsedImport: StudentCSVImporter.Parsed?
    @Binding var pendingFileURL: URL?
    let onFileImport: (Result<URL, Error>) -> Void
    let onMappingCancel: () -> Void
    let onMappingConfirm: (StudentCSVImporter.Mapping) -> Void
    let onImportCancel: () -> Void
    let onImportConfirm: (StudentCSVImporter.Parsed) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                onFileImport(result)
            }
            .sheet(isPresented: $showingMappingSheet) {
                StudentCSVMappingView(
                    headers: mappingHeaders,
                    onCancel: onMappingCancel,
                    onConfirm: onMappingConfirm
                )
            }
            .sheet(item: $pendingParsedImport, onDismiss: {}, content: { parsed in
                StudentImportPreviewView(
                    parsed: parsed,
                    onCancel: onImportCancel,
                    onConfirm: onImportConfirm
                )
                .frame(minWidth: 620, minHeight: 520)
            })
    }
}
