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
/// Displays and manages a lesson's attachments: its own, and those shared with
/// its whole sequence or area from whichever lesson holds them. A shared
/// attachment is renamed or deleted from the lesson that holds it; elsewhere
/// it can be viewed and shared.
struct LessonAttachmentsSection: View {
    private static let logger = Logger.lessons

    /// Why the Sample Class can't add files: its lessons are copies that point at
    /// the real notebook's files, and its file actions change records only.
    static let sampleClassFilesTitle = "Can't Add Files Here"
    static let sampleClassFilesMessage = "The Sample Class shares your class's lesson files, "
        + "so it can't add or change them. Switch to My Class to add a file."

    let lesson: CDLesson
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.isSampleClassroom) private var isSampleClassroom

    @State private var showingScopeSheet = false
    @State private var selectedScope: AttachmentScope = .lesson
    @State private var showingDeleteAlert = false
    @State private var attachmentToDelete: CDLessonAttachment?
    @State private var attachmentToRename: CDLessonAttachment?
    @State private var renameFileName = ""
    @State private var isDropTargeted = false
    /// The import sheet's "Move original to trash". It applies to that one
    /// import and is cleared after it: it used to stay on, and the next file
    /// dropped onto the section (an album PDF from Finder) went to the Trash.
    @State private var deleteOriginalAfterImport = false
    /// What went wrong with an attachment, shown in one alert; the raw error is logged.
    @State private var attachmentProblem: (title: String, message: String)?

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
                Text(deleteMessage(for: attachment))
            }
            .alert(
                attachmentProblem?.title ?? "",
                isPresented: Binding(
                    get: { attachmentProblem != nil },
                    set: { if !$0 { attachmentProblem = nil } }
                ),
                presenting: attachmentProblem?.message
            ) { _ in
                Button("OK", role: .cancel) { attachmentProblem = nil }
            } message: { message in
                Text(message)
            }
            .onDrop(of: [.pdf, .png, .jpeg, .fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }
    }

    private var attachmentsContent: some View {
        // One read per pass: the shared attachments come from a fetch.
        let attachments = LessonFileStorage.getAttachments(forLesson: lesson, includeInherited: true)
        let lessonAttachments = attachments.filter { $0.scope == .lesson }
        let sequenceAttachments = attachments.filter { $0.scope == .sequence }
        let areaAttachments = attachments.filter { $0.scope == .area }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Attachments", systemImage: "paperclip")
                    .font(AppTheme.ScaledFont.calloutBold)

                Spacer()

                Button(action: beginImport, label: {
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
                        attachmentGroup(title: "This Lesson", attachments: lessonAttachments)
                    }

                    if !sequenceAttachments.isEmpty {
                        attachmentGroup(
                            title: "From Sequence: \(lesson.sequence)",
                            attachments: sequenceAttachments
                        )
                    }

                    if !areaAttachments.isEmpty {
                        attachmentGroup(
                            title: "From Area: \(lesson.area)",
                            attachments: areaAttachments
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                .fill(Color.controlBackgroundColor())
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
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
                let trashOriginal = deleteOriginalAfterImport
                deleteOriginalAfterImport = false
                handleFileImport(result: result, scope: selectedScope, trashOriginal: trashOriginal)
            },
            onCancel: {
                showingScopeSheet = false
                deleteOriginalAfterImport = false
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

    private func attachmentGroup(title: String, attachments: [CDLessonAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(attachments, id: \.objectID) { attachment in
                AttachmentRow(
                    attachment: attachment,
                    // Shared from another lesson: view and share here, change it there.
                    isInherited: attachment.lesson?.objectID != lesson.objectID,
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

    private func deleteMessage(for attachment: CDLessonAttachment) -> String {
        switch attachment.scope {
        case .lesson:
            return "\(attachment.fileName) will be deleted. This can't be undone."
        case .sequence:
            return "\(attachment.fileName) will be deleted from every lesson in this sequence. This can't be undone."
        case .area:
            return "\(attachment.fileName) will be deleted from every lesson in this area. This can't be undone."
        }
    }

    // MARK: - Import

    /// Add: the import options, except in the Sample Class, which can't add files.
    private func beginImport() {
        if isSampleClassroom {
            attachmentProblem = (Self.sampleClassFilesTitle, Self.sampleClassFilesMessage)
        } else {
            showingScopeSheet = true
        }
    }

    /// Copies the picked or dropped file in and attaches it with `scope`. The
    /// original goes to the Trash only when `trashOriginal` (the import sheet's
    /// toggle, for that import) says so, never for a drop.
    private func handleFileImport(result: Result<[URL], Error>, scope: AttachmentScope, trashOriginal: Bool) {
        guard !isSampleClassroom else {
            attachmentProblem = (Self.sampleClassFilesTitle, Self.sampleClassFilesMessage)
            return
        }
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                Self.logger.error("No URL in result")
                return
            }
            importAttachment(from: url, scope: scope, trashOriginal: trashOriginal)

        case .failure(let error):
            Self.logger.error("File import error: \(error)")
            attachmentProblem = ("Couldn't Add the File", AppErrorMessages.importMessage(for: error))
        }
    }

    private func importAttachment(from url: URL, scope: AttachmentScope, trashOriginal: Bool) {
        FileImportHelpers.logImportAttempt(url: url)
        let needsSecurityScope = FileImportHelpers.accessSecurityScopedResource(url: url)

        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
                Self.logger.info("Stopped security-scoped access")
            }
        }

        do {
            let (destURL, relativePath) = try LessonFileStorage.importAttachment(
                from: url,
                forLesson: lesson,
                scope: scope
            )
            let fileSize = try FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64 ?? 0
            let bookmark = try LessonFileStorage.makeBookmark(for: destURL)
            FileImportHelpers.logImportSuccess(url: destURL, relativePath: relativePath, fileSize: fileSize)

            let attachment = CDLessonAttachment(context: viewContext)
            attachment.fileName = url.lastPathComponent
            attachment.fileBookmark = bookmark
            attachment.fileRelativePath = relativePath
            attachment.fileType = url.pathExtension.lowercased()
            attachment.fileSizeBytes = fileSize
            attachment.scope = scope
            attachment.lesson = lesson

            guard viewContext.safeSave() else {
                // Nothing points at the copy just made, so it can go.
                viewContext.delete(attachment)
                try? LessonFileStorage.deleteIfManaged(destURL)
                attachmentProblem = ("Couldn't Add the File", "Couldn't save the new attachment. Try again.")
                return
            }

            if trashOriginal {
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    Self.logger.info("Moved original file to trash: \(url.lastPathComponent)")
                } catch {
                    Self.logger.warning("Failed to delete original file: \(error)")
                }
            }
        } catch {
            FileImportHelpers.logImportError(error)
            attachmentProblem = ("Couldn't Add the File", AppErrorMessages.importMessage(for: error))
        }
    }

    // MARK: - Changes

    /// Deletes the attachment's record; its file goes to the Trash after the
    /// save when nothing else points at it. In the Sample Class only the record goes.
    private func deleteAttachment(_ attachment: CDLessonAttachment) {
        let holder = attachment.lesson
        let wasPrimary = holder?.primaryAttachmentIDUUID == attachment.id && attachment.id != nil
        let path = attachment.fileRelativePath
        // A failed save undoes just this delete, so it isn't saved later by
        // some other change after she was told to try again.
        let transaction = ContextMutationTransaction(context: viewContext)
        if wasPrimary { holder?.primaryAttachmentID = nil }
        viewContext.delete(attachment)
        guard viewContext.safeSave() else {
            transaction.rollback()
            attachmentProblem = ("Couldn't Delete the Attachment", "Couldn't delete this attachment. Try again.")
            return
        }
        transaction.commit()
        LessonFileStorage.trashUnreferencedFiles([path], in: viewContext, isSampleClassroom: isSampleClassroom)
    }

    private func togglePrimaryAttachment(_ attachment: CDLessonAttachment) {
        if lesson.primaryAttachmentIDUUID == attachment.id {
            lesson.primaryAttachmentID = nil
        } else {
            lesson.primaryAttachmentID = attachment.id?.uuidString
        }

        viewContext.safeSave()
    }

    /// Renames the file and the record. In the Sample Class only the name the
    /// record shows changes; the file stays as the real notebook has it.
    private func renameAttachment() {
        guard let attachment = attachmentToRename else { return }

        do {
            if isSampleClassroom {
                attachment.fileName = renameFileName.trimmed()
            } else {
                let renamedFile = try LessonFileStorage.renameAttachment(attachment, to: renameFileName)
                attachment.fileName = renamedFile.fileName
                attachment.fileRelativePath = renamedFile.relativePath
                attachment.fileBookmark = try LessonFileStorage.makeBookmark(for: renamedFile.url)
                attachment.fileType = renamedFile.fileType
            }
            if viewContext.safeSave() {
                attachmentToRename = nil
                renameFileName = ""
            } else {
                attachmentProblem = ("Couldn't Rename the Attachment", "Couldn't save the new name. Try again.")
            }
        } catch {
            Self.logger.error("Failed to rename attachment: \(error)")
            attachmentProblem = ("Couldn't Rename the Attachment", "Couldn't rename this attachment. Try again.")
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isSampleClassroom else {
            attachmentProblem = (Self.sampleClassFilesTitle, Self.sampleClassFilesMessage)
            return false
        }
        guard let provider = providers.first else {
            Self.logger.error("No provider")
            return false
        }

        // Debug: log all available type identifiers
        Self.logger.debug("Available type identifiers: \(provider.registeredTypeIdentifiers.joined(separator: ", "))")

        guard provider.canLoadObject(ofClass: URL.self) else {
            Self.logger.error("No compatible type found")
            return false
        }

        // Load the file URL asynchronously - don't block!
        let logger = Self.logger
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let fileURL = url else {
                if let error {
                    logger.error("Drop error: \(error)")
                } else {
                    logger.error("Failed to get URL from dropped item")
                }
                Task { @MainActor in
                    self.attachmentProblem = ("Couldn't Add the File", "Couldn't add the file you dropped. Try again.")
                }
                return
            }

            // A dropped file is copied in for this lesson; the original is never trashed.
            Task { @MainActor in
                self.handleFileImport(result: .success([fileURL]), scope: .lesson, trashOriginal: false)
            }
        }

        // Return true immediately to accept the drop
        return true
    }
}
// swiftlint:enable type_body_length

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct LessonAttachmentsSectionPreview: View {
    var body: some View {
        let ctx = CoreDataStack.preview.viewContext
        let lesson = CDLesson(context: ctx)
        lesson.name = "Introduction to Place Value"
        lesson.area = "Math"
        lesson.sequence = "Decimal System"

        return LessonAttachmentsSection(lesson: lesson)
            .previewEnvironment()
            .frame(width: 500)
            .padding()
    }
}

#Preview {
    LessonAttachmentsSectionPreview()
}
