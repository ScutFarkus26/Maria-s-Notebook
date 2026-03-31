import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

/// Global handler for importing attachments from anywhere in the app
@MainActor
@Observable
class GlobalAttachmentImportHandler {
    private static let logger = Logger.lessons

    var isShowingImportSheet = false
    var pendingFileURL: URL?
    var preselectedLesson: CDLesson?
    
    let viewContext: NSManagedObjectContext
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    /// Import a file with automatic lesson detection
    func importFile(_ fileURL: URL) {
        pendingFileURL = fileURL
        preselectedLesson = nil
        isShowingImportSheet = true
    }
    
    /// Import a file for a specific lesson (skips lesson selection)
    func importFile(_ fileURL: URL, forLesson lesson: CDLesson, scope: AttachmentScope = .lesson) {
        Task {
            await performImport(fileURL: fileURL, lesson: lesson, scope: scope)
        }
    }
    
    /// Import a file with a preselected lesson suggestion
    func importFileWithSuggestion(_ fileURL: URL, suggestedLesson: CDLesson?) {
        pendingFileURL = fileURL
        preselectedLesson = suggestedLesson
        isShowingImportSheet = true
    }
    
    /// Performs the actual import operation
    func performImport(fileURL: URL, lesson: CDLesson, scope: AttachmentScope) async {
        // Start accessing security-scoped resource
        guard fileURL.startAccessingSecurityScopedResource() else {
            Self.logger.error("Failed to access file")
            return
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }
        
        do {
            // Import the file
            let (destURL, relativePath) = try LessonFileStorage.importAttachment(
                from: fileURL,
                forLesson: lesson,
                scope: scope
            )
            
            // Get file size
            let fileSize = try FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64 ?? 0
            
            // Create bookmark
            let bookmark = try LessonFileStorage.makeBookmark(for: destURL)
            
            // Create attachment entity
            let attachment = CDLessonAttachment(context: viewContext)
            attachment.fileName = fileURL.lastPathComponent
            attachment.fileBookmark = bookmark
            attachment.fileRelativePath = relativePath
            attachment.fileType = fileURL.pathExtension.lowercased()
            attachment.fileSizeBytes = fileSize
            attachment.scope = scope
            attachment.lesson = lesson
            try viewContext.save()
            
            Self.logger.info("Successfully imported attachment: \(fileURL.lastPathComponent)")

        } catch {
            Self.logger.error("Failed to import attachment: \(error)")
        }
    }
}

/// View modifier to add global attachment import capability
struct GlobalAttachmentImportModifier: ViewModifier {
    @State private var importHandler: GlobalAttachmentImportHandler
    
    init(viewContext: NSManagedObjectContext) {
        _importHandler = State(wrappedValue: GlobalAttachmentImportHandler(viewContext: viewContext))
    }
    
    func body(content: Content) -> some View {
        content
            .environment(importHandler)
            .sheet(isPresented: $importHandler.isShowingImportSheet) {
                if let fileURL = importHandler.pendingFileURL {
                    LessonAttachmentImportSheet(
                        fileURL: fileURL,
                        onImport: { lesson, scope in
                            importHandler.isShowingImportSheet = false
                            Task {
                                await importHandler.performImport(
                                    fileURL: fileURL,
                                    lesson: lesson,
                                    scope: scope
                                )
                            }
                        },
                        onCancel: {
                            importHandler.isShowingImportSheet = false
                            importHandler.pendingFileURL = nil
                        }
                    )
                }
            }
    }
}

extension View {
    /// Adds global attachment import capability to the view
    func withGlobalAttachmentImport(viewContext: NSManagedObjectContext) -> some View {
        modifier(GlobalAttachmentImportModifier(viewContext: viewContext))
    }
}

/// Quick action button for importing attachments
struct QuickAttachmentImportButton: View {
    private static let logger = Logger.lessons

    let lesson: CDLesson
    @Environment(GlobalAttachmentImportHandler.self) private var importHandler
    @State private var showingFilePicker = false
    
    var body: some View {
        Button(action: { showingFilePicker = true }, label: {
            Label("Add Attachment", systemImage: "paperclip")
        })
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .png, .jpeg, UTType(filenameExtension: "pages") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importHandler.importFileWithSuggestion(url, suggestedLesson: lesson)
                }
            case .failure(let error):
                Self.logger.error("File picker error: \(error)")
            }
        }
    }
}

/// Drag and drop handler for attachments
struct AttachmentDropDelegate: DropDelegate {
    let lesson: CDLesson
    let importHandler: GlobalAttachmentImportHandler
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.pdf, .png, .jpeg, .fileURL])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.fileURL]).first else {
            return false
        }
        
        itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            
            Task { @MainActor in
                importHandler.importFile(url, forLesson: lesson, scope: .lesson)
            }
        }
        
        return true
    }
}

/// Extension to add drop capability to lesson cards
extension View {
    func lessonAttachmentDropTarget(lesson: CDLesson, importHandler: GlobalAttachmentImportHandler) -> some View {
        self.onDrop(
            of: [.pdf, .png, .jpeg, .fileURL],
            delegate: AttachmentDropDelegate(lesson: lesson, importHandler: importHandler)
        )
    }
}
