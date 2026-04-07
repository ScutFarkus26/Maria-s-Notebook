// swiftlint:disable file_length
import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

// MARK: - File Import Helpers

private enum FileImportHelpers {
    private static let logger = Logger.lessons

    static func accessSecurityScopedResource(url: URL) -> Bool {
        let needsAccess = url.startAccessingSecurityScopedResource()
        if needsAccess {
            logger.info("Started security-scoped access")
        } else {
            logger.debug("File accessible without security scope")
        }
        return needsAccess
    }

    static func logImportAttempt(url: URL) {
        logger.debug("Attempting to import: \(url.lastPathComponent) from path: \(url.path)")
    }

    static func logImportSuccess(url: URL, relativePath: String, fileSize: Int64) {
        logger.info("File copied to: \(url.path), relative path: \(relativePath), size: \(fileSize) bytes")
        logger.info("Successfully imported attachment: \(url.lastPathComponent)")
    }

    static func logImportError(_ error: Error) {
        logger.error("Failed to import attachment: \(error)")
        if let nsError = error as NSError? {
            logger.error("Error domain: \(nsError.domain), code: \(nsError.code)")
        }
    }
}

// swiftlint:disable type_body_length
/// Displays and manages attachments for a lesson, including inherited attachments from group and subject.
struct LessonAttachmentsSection: View {
    private static let logger = Logger.lessons

    let lesson: CDLesson
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var showingScopeSheet = false
    @State private var selectedScope: AttachmentScope = .lesson
    @State private var pendingImportURL: URL?
    @State private var showingDeleteAlert = false
    @State private var attachmentToDelete: CDLessonAttachment?
    @State private var attachmentToRename: CDLessonAttachment?
    @State private var renameFileName = ""
    @State private var isDropTargeted = false
    @State private var deleteOriginalAfterImport = false
    
    private var attachments: [CDLessonAttachment] {
        LessonFileStorage.getAttachments(forLesson: lesson, includeInherited: true)
    }
    
    private var lessonAttachments: [CDLessonAttachment] {
        attachments.filter { $0.scope == .lesson }
    }
    
    private var groupAttachments: [CDLessonAttachment] {
        attachments.filter { $0.scope == .group }
    }
    
    private var subjectAttachments: [CDLessonAttachment] {
        attachments.filter { $0.scope == .subject }
    }
    
    var body: some View {
        attachmentsContent
            .sheet(isPresented: $showingScopeSheet) {
                scopeSheet
            }
            .alert(
                "Rename Attachment",
                isPresented: Binding(
                    get: { attachmentToRename != nil },
                    set: { isPresented in
                        if !isPresented {
                            attachmentToRename = nil
                            renameFileName = ""
                        }
                    }
                )
            ) {
                TextField("Name", text: $renameFileName)
                Button("Cancel", role: .cancel) {
                    attachmentToRename = nil
                    renameFileName = ""
                }
                Button("Save") {
                    renameAttachment()
                }
                .disabled(renameFileName.trimmed().isEmpty)
            } message: {
                Text("Choose a new name for this attachment.")
            }
            .alert(
                "Delete Attachment?",
                isPresented: $showingDeleteAlert,
                presenting: attachmentToDelete
            ) { attachment in
                Button("Delete", role: .destructive) {
                    deleteAttachment(attachment)
                }
                Button("Cancel", role: .cancel) {}
            } message: { attachment in
                Text("This will permanently delete \(attachment.fileName)")
            }
            .onDrop(of: [.pdf, .png, .jpeg, .fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }
    }

    private var attachmentsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Attachments", systemImage: "paperclip")
                    .font(AppTheme.ScaledFont.calloutBold)

                Spacer()

                Button(action: { showingScopeSheet = true }, label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(AppTheme.ScaledFont.bodySemibold)
                })
                .buttonStyle(.borderless)
            }

            if attachments.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !lessonAttachments.isEmpty {
                        attachmentGroup(
                            title: "This Lesson", attachments: lessonAttachments
                        )
                    }

                    if !groupAttachments.isEmpty {
                        attachmentGroup(
                            title: "From Group: \(lesson.group)",
                            attachments: groupAttachments, isInherited: true
                        )
                    }

                    if !subjectAttachments.isEmpty {
                        attachmentGroup(
                            title: "From Subject: \(lesson.subject)",
                            attachments: subjectAttachments, isInherited: true
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.controlBackgroundColor())
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [5, 3])
                        )
                )
        )
    }

    private var scopeSheet: some View {
        AttachmentImportOptionsSheet(
            lesson: lesson,
            selectedScope: $selectedScope,
            deleteOriginal: $deleteOriginalAfterImport,
            onFileSelected: { result in
                showingScopeSheet = false
                handleFileImport(result: result)
            },
            onCancel: {
                showingScopeSheet = false
            }
        )
        .frame(minWidth: 400, idealWidth: 400, minHeight: 480, idealHeight: 480)
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No attachments yet")
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.secondary)
            Text("Add PDFs, images, or Pages documents")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    private func attachmentGroup(
        title: String, attachments: [CDLessonAttachment], isInherited: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            ForEach(attachments, id: \.id) { attachment in
                AttachmentRow(
                    attachment: attachment,
                    isInherited: isInherited,
                    isPrimary: lesson.primaryAttachmentIDUUID == attachment.id,
                    onTogglePrimary: {
                        togglePrimaryAttachment(attachment)
                    },
                    onRename: {
                        attachmentToRename = attachment
                        renameFileName = attachment.fileName
                    },
                    onDelete: {
                        attachmentToDelete = attachment
                        showingDeleteAlert = true
                    }
                )
            }
        }
    }
    
    // swiftlint:disable:next function_body_length
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                Self.logger.error("No URL in result")
                return
            }
            
            FileImportHelpers.logImportAttempt(url: url)
            let needsSecurityScope = FileImportHelpers.accessSecurityScopedResource(url: url)
            
            defer {
                if needsSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                    Self.logger.info("Stopped security-scoped access")
                }
            }
            
            do {
                Self.logger.debug("Getting organizational directory for lesson: \(lesson.name)")
                
                // Import the file
                let (destURL, relativePath) = try LessonFileStorage.importAttachment(
                    from: url,
                    forLesson: lesson,
                    scope: selectedScope
                )
                
                // Get file size
                let fileSize = try FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64 ?? 0
                
                // Create bookmark
                let bookmark = try LessonFileStorage.makeBookmark(for: destURL)
                
                FileImportHelpers.logImportSuccess(url: destURL, relativePath: relativePath, fileSize: fileSize)
                
                // Create attachment entity
                let attachment = CDLessonAttachment(context: viewContext)
                attachment.fileName = url.lastPathComponent
                attachment.fileBookmark = bookmark
                attachment.fileRelativePath = relativePath
                attachment.fileType = url.pathExtension.lowercased()
                attachment.fileSizeBytes = fileSize
                attachment.scope = selectedScope
                attachment.lesson = lesson
                
                Self.logger.debug("Saving context")
                try viewContext.save()
                
                // Delete original file if requested
                if deleteOriginalAfterImport {
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        Self.logger.info("Moved original file to trash: \(url.lastPathComponent)")
                    } catch {
                        Self.logger.warning("Failed to delete original file: \(error)")
                    }
                }
                
            } catch {
                FileImportHelpers.logImportError(error)
            }
            
        case .failure(let error):
            Self.logger.error("File import error: \(error)")
        }
    }
    
    private func deleteAttachment(_ attachment: CDLessonAttachment) {
        do {
            if lesson.primaryAttachmentIDUUID == attachment.id {
                lesson.primaryAttachmentID = nil
            }

            // Delete the file if it's managed
            if !attachment.fileRelativePath.isEmpty {
                let fileURL = try LessonFileStorage.resolve(relativePath: attachment.fileRelativePath)
                try LessonFileStorage.deleteIfManaged(fileURL)
            }
            
            // Delete the attachment entity
            viewContext.delete(attachment)
            try viewContext.save()
            
        } catch {
            Self.logger.error("Failed to delete attachment: \(error)")
        }
    }

    private func togglePrimaryAttachment(_ attachment: CDLessonAttachment) {
        if lesson.primaryAttachmentIDUUID == attachment.id {
            lesson.primaryAttachmentID = nil
        } else {
            lesson.primaryAttachmentID = attachment.id?.uuidString
        }

        do {
            try viewContext.save()
        } catch {
            Self.logger.error("Failed to update primary attachment: \(error)")
        }
    }

    private func renameAttachment() {
        guard let attachment = attachmentToRename else { return }

        do {
            let renamedFile = try LessonFileStorage.renameAttachment(attachment, to: renameFileName)
            attachment.fileName = renamedFile.fileName
            attachment.fileRelativePath = renamedFile.relativePath
            attachment.fileBookmark = try LessonFileStorage.makeBookmark(for: renamedFile.url)
            attachment.fileType = renamedFile.fileType
            try viewContext.save()

            attachmentToRename = nil
            renameFileName = ""
        } catch {
            Self.logger.error("Failed to rename attachment: \(error)")
        }
    }

    // swiftlint:disable:next function_body_length
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            Self.logger.error("No provider")
            return false
        }

        // Debug: log all available type identifiers
        Self.logger.debug("Available type identifiers: \(provider.registeredTypeIdentifiers.joined(separator: ", "))")
        
        // Try multiple type identifiers that might work
        let typeIdentifiers = [
            "public.file-url",
            UTType.fileURL.identifier,
            "public.url",
            UTType.url.identifier,
            "public.data"
        ]
        
        var foundType: String?
        for typeId in typeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeId) {
            Self.logger.info("Found conforming type: \(typeId)")
            foundType = typeId
            break
        }
        
        guard let typeIdentifier = foundType else {
            Self.logger.error("No compatible type found")
            return false
        }
        
        // Load the file URL asynchronously - don't block!
        let logger = Self.logger
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
            if let error {
                logger.error("Drop error: \(error)")
                return
            }

            logger.debug("Received item type: \(String(describing: type(of: item)))")

            var url: URL?

            // Handle different data types
            if let urlItem = item as? URL {
                url = urlItem
                logger.info("Got URL directly: \(urlItem.path)")
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
                logger.info("Got URL from Data: \(url?.path ?? "nil")")
            } else if let string = item as? String {
                url = URL(string: string)
                logger.info("Got URL from String: \(url?.path ?? "nil")")
            } else {
                logger.error("Unknown item type: \(String(describing: type(of: item)))")
            }

            guard let fileURL = url else {
                logger.error("Failed to get URL from dropped item")
                return
            }
            
            // Import on main thread
            Task { @MainActor in
                self.selectedScope = .lesson
                self.handleFileImport(result: .success([fileURL]))
            }
        }
        
        // Return true immediately to accept the drop
        return true
    }
}
// swiftlint:enable type_body_length

#Preview {
    let ctx = CoreDataStack.preview.viewContext
    let lesson = CDLesson(context: ctx)
    lesson.name = "Introduction to Place Value"
    lesson.subject = "Math"
    lesson.group = "Decimal System"

    return LessonAttachmentsSection(lesson: lesson)
        .previewEnvironment()
        .frame(width: 500)
        .padding()
}
