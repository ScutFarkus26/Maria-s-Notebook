import SwiftUI
import SwiftData
@preconcurrency import PDFKit
import OSLog

/// Detail view for a single resource, showing PDF preview, metadata, and edit/delete actions.
struct ResourceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var resource: Resource

    @Query(sort: [SortDescriptor(\Lesson.name)]) private var allLessons: [Lesson]

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editCategory: ResourceCategory = .other
    @State private var editDescription = ""
    @State private var editTags: [String] = []
    @State private var editLessonIDs: Set<UUID> = []
    @State private var editSubjects: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var pdfPage: PDFPage?

    private static let logger = Logger.resources

    private var availableSubjects: [String] {
        let unique = Set(allLessons.map { $0.subject.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        return Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var linkedLessonIDSet: Set<UUID> {
        Set(
            resource.linkedLessonIDs
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) }
        )
    }

    private var linkedSubjectSet: [String] {
        resource.linkedSubjects
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var linkedLessons: [Lesson] {
        let ids = linkedLessonIDSet
        return allLessons.filter { ids.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // PDF Preview
                    pdfPreview

                    Divider()

                    // Metadata
                    metadataSection

                    // Tags
                    if !resource.tags.isEmpty {
                        tagsSection
                    }

                    // Linked Subjects & Lessons
                    if !linkedSubjectSet.isEmpty || !linkedLessons.isEmpty {
                        linkingSection
                    }

                    // Description
                    if !resource.descriptionText.isEmpty {
                        descriptionSection
                    }
                }
                .padding(24)
            }
            .navigationTitle(resource.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: resource.isFavorite ? SFSymbol.Shape.starFill : SFSymbol.Shape.star)
                            .foregroundStyle(resource.isFavorite ? .yellow : .secondary)
                    }

                    Button {
                        startEditing()
                    } label: {
                        Image(systemName: SFSymbol.Education.pencil)
                    }

                    Menu {
                        Button {
                            openInDefaultApp()
                        } label: {
                            Label("Open PDF", systemImage: "arrow.up.forward.square")
                        }

                        if let fileURL = resolvedFileURL {
                            ShareLink(item: fileURL) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }

                            #if os(iOS)
                            Button {
                                printResource()
                            } label: {
                                Label("Print", systemImage: "printer")
                            }
                            #endif
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: SFSymbol.Action.trash)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                editSheet
            }
            .confirmationDialog("Delete Resource?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    deleteResource()
                }
            } message: {
                Text("This will permanently delete \"\(resource.title)\" and its file.")
            }
        }
        .task {
            loadPDF()
            markViewed()
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    // MARK: - PDF Preview

    private var pdfPreview: some View {
        Group {
            if let pdfPage {
                PDFThumbnailView(page: pdfPage)
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.08))
                    )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("PDF Preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            metadataRow(label: "Category", icon: resource.category.icon) {
                Text(resource.category.rawValue)
            }

            if resource.fileSizeBytes > 0 {
                metadataRow(label: "File Size", icon: "doc") {
                    Text(resource.fileSizeFormatted)
                }
            }

            metadataRow(label: "Added", icon: "calendar") {
                Text(resource.createdAt, style: .date)
            }

            if resource.modifiedAt != resource.createdAt {
                metadataRow(label: "Modified", icon: "pencil") {
                    Text(resource.modifiedAt, style: .date)
                }
            }
        }
    }

    private func metadataRow<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            content()
                .font(.subheadline)
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(resource.tags, id: \.self) { tag in
                    TagBadge(tag: tag)
                }
            }
        }
    }

    // MARK: - Linked Subjects & Lessons

    private var linkingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !linkedSubjectSet.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Linked Subjects")
                        .font(.headline)

                    FlowLayout(spacing: 8) {
                        ForEach(linkedSubjectSet, id: \.self) { subject in
                            Text(subject)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.accentColor.opacity(0.15))
                                )
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            if !linkedLessons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Linked Lessons")
                        .font(.headline)

                    ForEach(linkedLessons) { lesson in
                        HStack(spacing: 8) {
                            Image(systemName: "book")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(lesson.name)
                                .font(.subheadline)
                            if !lesson.subject.isEmpty {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(lesson.subject)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            Text(resource.descriptionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $editTitle)

                    Picker("Category", selection: $editCategory) {
                        ForEach(ResourceCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                }

                Section("Tags") {
                    TagPicker(selectedTags: $editTags)
                }

                Section("Link to Subjects") {
                    if availableSubjects.isEmpty {
                        Text("No subjects available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableSubjects, id: \.self) { subject in
                            Button {
                                if editSubjects.contains(subject) {
                                    editSubjects.remove(subject)
                                } else {
                                    editSubjects.insert(subject)
                                }
                            } label: {
                                HStack {
                                    Text(subject)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if editSubjects.contains(subject) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Link to Lessons") {
                    if allLessons.isEmpty {
                        Text("No lessons available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ResourceLessonPicker(
                            allLessons: allLessons,
                            selectedLessonIDs: $editLessonIDs
                        )
                    }
                }

                Section("Notes") {
                    TextField("Description or usage notes", text: $editDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Resource")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditing = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEdits()
                    }
                    .disabled(editTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    // MARK: - File Access

    private var resolvedFileURL: URL? {
        guard !resource.fileRelativePath.isEmpty else { return nil }
        return try? ResourceFileStorage.resolve(relativePath: resource.fileRelativePath)
    }

    // MARK: - Actions

    private func loadPDF() {
        guard !resource.fileRelativePath.isEmpty else { return }
        do {
            let url = try ResourceFileStorage.resolve(relativePath: resource.fileRelativePath)
            if let document = PDFDocument(url: url) {
                pdfPage = document.page(at: 0)
            }
        } catch {
            Self.logger.warning("Failed to load PDF: \(error, privacy: .public)")
        }
    }

    private func markViewed() {
        resource.lastViewedAt = Date()
    }

    private func toggleFavorite() {
        resource.isFavorite.toggle()
        resource.modifiedAt = Date()
        modelContext.safeSave()
    }

    private func startEditing() {
        editTitle = resource.title
        editCategory = resource.category
        editDescription = resource.descriptionText
        editTags = resource.tags
        editLessonIDs = linkedLessonIDSet
        editSubjects = Set(linkedSubjectSet)
        isEditing = true
    }

    private func saveEdits() {
        resource.title = editTitle.trimmingCharacters(in: .whitespaces)
        resource.category = editCategory
        resource.descriptionText = editDescription.trimmingCharacters(in: .whitespaces)
        resource.tags = editTags
        resource.linkedLessonIDs = editLessonIDs.map { $0.uuidString }.sorted().joined(separator: ",")
        resource.linkedSubjects = editSubjects.sorted().joined(separator: ",")
        resource.modifiedAt = Date()
        modelContext.safeSave()
        isEditing = false
    }

    private func openInDefaultApp() {
        guard !resource.fileRelativePath.isEmpty else { return }
        do {
            let url = try ResourceFileStorage.resolve(relativePath: resource.fileRelativePath)
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            // On iOS, create a temporary copy and use UIApplication to open
            if let pdfData = try? Data(contentsOf: url) {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(resource.title.isEmpty ? "Resource.pdf" : "\(resource.title).pdf")
                try? pdfData.write(to: tempURL)
                UIApplication.shared.open(tempURL)
            }
            #endif
        } catch {
            Self.logger.warning("Failed to open PDF: \(error, privacy: .public)")
        }
    }

    #if os(iOS)
    private func printResource() {
        guard let url = resolvedFileURL,
              let data = try? Data(contentsOf: url) else { return }
        let printController = UIPrintInteractionController.shared
        printController.printingItem = data
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = resource.title
        printInfo.outputType = .general
        printController.printInfo = printInfo
        printController.present(animated: true)
    }
    #endif

    private func deleteResource() {
        let repo = ResourceRepository(context: modelContext)
        repo.deleteResource(resource)
        modelContext.safeSave()
        dismiss()
    }
}
