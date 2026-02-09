import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Displays and manages attachments for a lesson, including inherited attachments from group and subject.
struct LessonAttachmentsSection: View {
    let lesson: Lesson
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingImporter = false
    @State private var showingScopeSheet = false
    @State private var selectedScope: AttachmentScope = .lesson
    @State private var pendingImportURL: URL?
    @State private var showingDeleteAlert = false
    @State private var attachmentToDelete: LessonAttachment?
    @State private var isDropTargeted = false
    @State private var deleteOriginalAfterImport = false
    
    private var attachments: [LessonAttachment] {
        LessonFileStorage.getAttachments(forLesson: lesson, includeInherited: true)
    }
    
    private var lessonAttachments: [LessonAttachment] {
        attachments.filter { $0.scope == .lesson }
    }
    
    private var groupAttachments: [LessonAttachment] {
        attachments.filter { $0.scope == .group }
    }
    
    private var subjectAttachments: [LessonAttachment] {
        attachments.filter { $0.scope == .subject }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Attachments", systemImage: "paperclip")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                
                Spacer()
                
                Button(action: { showingScopeSheet = true }) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
            }
            
            if attachments.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !lessonAttachments.isEmpty {
                        attachmentGroup(title: "This Lesson", attachments: lessonAttachments)
                    }
                    
                    if !groupAttachments.isEmpty {
                        attachmentGroup(title: "From Group: \(lesson.group)", attachments: groupAttachments, isInherited: true)
                    }
                    
                    if !subjectAttachments.isEmpty {
                        attachmentGroup(title: "From Subject: \(lesson.subject)", attachments: subjectAttachments, isInherited: true)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [5, 3])
                        )
                )
        )
        .sheet(isPresented: $showingScopeSheet) {
            AttachmentImportOptionsSheet(
                lesson: lesson,
                selectedScope: $selectedScope,
                deleteOriginal: $deleteOriginalAfterImport,
                onImport: {
                    showingScopeSheet = false
                    showingImporter = true
                },
                onCancel: {
                    showingScopeSheet = false
                }
            )
            .frame(width: 400, height: 300)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf, .png, .jpeg, UTType(filenameExtension: "pages") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
        .alert("Delete Attachment?", isPresented: $showingDeleteAlert, presenting: attachmentToDelete) { attachment in
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
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No attachments yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Text("Add PDFs, images, or Pages documents")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    private func attachmentGroup(title: String, attachments: [LessonAttachment], isInherited: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            ForEach(attachments) { attachment in
                AttachmentRow(
                    attachment: attachment,
                    isInherited: isInherited,
                    onDelete: {
                        attachmentToDelete = attachment
                        showingDeleteAlert = true
                    }
                )
            }
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                print("❌ No URL in result")
                return
            }
            
            print("📁 Attempting to import: \(url.lastPathComponent)")
            print("📍 From path: \(url.path)")
            
            // For drag and drop from Finder, files are usually accessible without security-scoped access
            // Try to access without security scope first
            let needsSecurityScope = url.startAccessingSecurityScopedResource()
            if needsSecurityScope {
                print("✅ Started security-scoped access")
            } else {
                print("ℹ️ File accessible without security scope")
            }
            
            defer {
                if needsSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                    print("✅ Stopped security-scoped access")
                }
            }
            
            do {
                print("📂 Getting organizational directory for lesson: \(lesson.name)")
                
                // Import the file
                let (destURL, relativePath) = try LessonFileStorage.importAttachment(
                    from: url,
                    forLesson: lesson,
                    scope: selectedScope
                )
                
                print("✅ File copied to: \(destURL.path)")
                print("📍 Relative path: \(relativePath)")
                
                // Get file size
                let fileSize = try FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64 ?? 0
                print("📊 File size: \(fileSize) bytes")
                
                // Create bookmark
                let bookmark = try LessonFileStorage.makeBookmark(for: destURL)
                print("🔖 Bookmark created")
                
                // Create attachment entity
                let attachment = LessonAttachment(
                    fileName: url.lastPathComponent,
                    fileBookmark: bookmark,
                    fileRelativePath: relativePath,
                    fileType: url.pathExtension.lowercased(),
                    fileSizeBytes: fileSize,
                    scope: selectedScope,
                    lesson: lesson
                )
                
                print("💾 Inserting attachment into context")
                modelContext.insert(attachment)
                
                print("💾 Saving context")
                try modelContext.save()
                
                print("✅ Successfully imported attachment: \(url.lastPathComponent)")
                
                // Delete original file if requested
                if deleteOriginalAfterImport {
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        print("🗑️ Moved original file to trash: \(url.lastPathComponent)")
                    } catch {
                        print("⚠️ Failed to delete original file: \(error)")
                    }
                }
                
            } catch {
                print("❌ Failed to import attachment: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                    print("❌ Error userInfo: \(nsError.userInfo)")
                }
            }
            
        case .failure(let error):
            print("❌ File import error: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }
    
    private func deleteAttachment(_ attachment: LessonAttachment) {
        do {
            // Delete the file if it's managed
            if !attachment.fileRelativePath.isEmpty {
                let fileURL = try LessonFileStorage.resolve(relativePath: attachment.fileRelativePath)
                try LessonFileStorage.deleteIfManaged(fileURL)
            }
            
            // Delete the attachment entity
            modelContext.delete(attachment)
            try modelContext.save()
            
        } catch {
            print("Failed to delete attachment: \(error)")
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            print("❌ No provider")
            return false
        }
        
        // Debug: print all available type identifiers
        print("📋 Available type identifiers:")
        provider.registeredTypeIdentifiers.forEach { identifier in
            print("  - \(identifier)")
        }
        
        // Try multiple type identifiers that might work
        let typeIdentifiers = [
            "public.file-url",
            UTType.fileURL.identifier,
            "public.url",
            UTType.url.identifier,
            "public.data"
        ]
        
        var foundType: String?
        for typeId in typeIdentifiers {
            if provider.hasItemConformingToTypeIdentifier(typeId) {
                print("✅ Found conforming type: \(typeId)")
                foundType = typeId
                break
            }
        }
        
        guard let typeIdentifier = foundType else {
            print("❌ No compatible type found")
            return false
        }
        
        // Load the file URL asynchronously - don't block!
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
            if let error = error {
                print("❌ Drop error: \(error)")
                return
            }
            
            print("📦 Received item type: \(type(of: item))")
            
            var url: URL?
            
            // Handle different data types
            if let urlItem = item as? URL {
                url = urlItem
                print("✅ Got URL directly: \(urlItem.path)")
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
                print("✅ Got URL from Data: \(url?.path ?? "nil")")
            } else if let string = item as? String {
                url = URL(string: string)
                print("✅ Got URL from String: \(url?.path ?? "nil")")
            } else {
                print("❌ Unknown item type: \(type(of: item))")
            }
            
            guard let fileURL = url else {
                print("❌ Failed to get URL from dropped item")
                return
            }
            
            // Import on main thread
            DispatchQueue.main.async {
                self.selectedScope = .lesson
                self.handleFileImport(result: .success([fileURL]))
            }
        }
        
        // Return true immediately to accept the drop
        return true
    }
}

/// Row view for displaying a single attachment
struct AttachmentRow: View {
    let attachment: LessonAttachment
    let isInherited: Bool
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // File type icon
            fileIcon
                .frame(width: 32, height: 32)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(attachment.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    if isInherited {
                        Image(systemName: attachment.scope.icon)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(attachment.fileSizeFormatted)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(attachment.attachedAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            if isHovering || isInherited {
                HStack(spacing: 8) {
                    Button(action: { openAttachment() }) {
                        Image(systemName: "eye")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("View")
                    
                    Button(action: { shareAttachment() }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Share")
                    
                    if !isInherited {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete")
                    }
                }
            }
        }
        .padding(8)
        .background(isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var fileIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(fileTypeColor.opacity(0.1))
            
            Image(systemName: fileTypeIcon)
                .font(.system(size: 16))
                .foregroundColor(fileTypeColor)
        }
    }
    
    private var fileTypeColor: Color {
        switch attachment.fileType {
        case "pdf": return .red
        case "pages": return .orange
        case "jpg", "jpeg", "png": return .blue
        default: return .gray
        }
    }
    
    private var fileTypeIcon: String {
        switch attachment.fileType {
        case "pdf": return "doc.fill"
        case "pages": return "doc.richtext.fill"
        case "jpg", "jpeg", "png": return "photo.fill"
        default: return "doc"
        }
    }
    
    private func openAttachment() {
        do {
            let fileURL = try LessonFileStorage.resolve(relativePath: attachment.fileRelativePath)
            NSWorkspace.shared.open(fileURL)
        } catch {
            print("Failed to open attachment: \(error)")
        }
    }
    
    private func shareAttachment() {
        do {
            let fileURL = try LessonFileStorage.resolve(relativePath: attachment.fileRelativePath)
            let picker = NSSharingServicePicker(items: [fileURL])
            if let view = NSApp.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        } catch {
            print("Failed to share attachment: \(error)")
        }
    }
}

/// Sheet for selecting import options
struct AttachmentImportOptionsSheet: View {
    let lesson: Lesson
    @Binding var selectedScope: AttachmentScope
    @Binding var deleteOriginal: Bool
    let onImport: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                
                Text("Import Options")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 16) {
                // Scope selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attachment Scope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        ScopeOptionButton(
                            scope: .lesson,
                            selectedScope: $selectedScope,
                            lesson: lesson
                        )
                        
                        ScopeOptionButton(
                            scope: .group,
                            selectedScope: $selectedScope,
                            lesson: lesson
                        )
                        
                        ScopeOptionButton(
                            scope: .subject,
                            selectedScope: $selectedScope,
                            lesson: lesson
                        )
                    }
                }
                
                Divider()
                
                // Delete original option
                Toggle(isOn: $deleteOriginal) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Move original to trash")
                            .font(.system(size: 13, weight: .medium))
                        Text("Delete the original file after importing")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Continue") {
                    onImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 20)
        }
    }
}

/// Button for selecting attachment scope
struct ScopeOptionButton: View {
    let scope: AttachmentScope
    @Binding var selectedScope: AttachmentScope
    let lesson: Lesson
    
    private var isSelected: Bool {
        selectedScope == scope
    }
    
    private var subtitle: String {
        switch scope {
        case .lesson:
            return "Only visible in this lesson"
        case .group:
            return "Visible in all lessons in \"\(lesson.group)\""
        case .subject:
            return "Visible in all lessons in \"\(lesson.subject)\""
        }
    }
    
    var body: some View {
        Button(action: { selectedScope = scope }) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Lesson.self, LessonAttachment.self, configurations: config)
    
    let lesson = Lesson(
        name: "Introduction to Place Value",
        subject: "Math",
        group: "Decimal System"
    )
    container.mainContext.insert(lesson)
    
    // Add some sample attachments
    let attachment1 = LessonAttachment(
        fileName: "Teacher Guide.pdf",
        fileRelativePath: "Math/Decimal System/Teacher Guide.pdf",
        fileType: "pdf",
        fileSizeBytes: 1024 * 1024 * 12,
        scope: .lesson,
        lesson: lesson
    )
    container.mainContext.insert(attachment1)
    
    let attachment2 = LessonAttachment(
        fileName: "Practice Sheets.pdf",
        fileRelativePath: "Math/Decimal System/Practice Sheets.pdf",
        fileType: "pdf",
        fileSizeBytes: 1024 * 1024 * 2,
        scope: .group,
        lesson: lesson
    )
    container.mainContext.insert(attachment2)
    
    return LessonAttachmentsSection(lesson: lesson)
        .modelContainer(container)
        .frame(width: 500)
        .padding()
}
