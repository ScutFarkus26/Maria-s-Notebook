// swiftlint:disable file_length
import SwiftUI
import CoreData
@preconcurrency import PDFKit
import OSLog

// Detail view for a single resource, showing PDF preview, metadata, and edit/delete actions.
// swiftlint:disable:next type_body_length
struct ResourceDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var resource: CDResource

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)])
    private var allLessons: FetchedResults<CDLesson>

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editCategory: ResourceCategory = .other
    @State private var editDescription = ""
    @State private var editTags: [String] = []
    @State private var editLessonIDs: Set<UUID> = []
    @State private var editAreas: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var pdfPage: PDFPage?

    private static let logger = Logger.resources

    private var availableAreas: [String] {
        let unique = Set(allLessons.map { $0.area.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        return Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var linkedLessonIDSet: Set<UUID> {
        Set(
            resource.linkedLessonIDs
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) }
        )
    }

    private var linkedAreaSet: [String] {
        resource.linkedAreas
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var linkedLessons: [CDLesson] {
        let ids = linkedLessonIDSet
        return allLessons.filter { lesson in
            guard let lessonID = lesson.id else { return false }
            return ids.contains(lessonID)
        }
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
                    if !resource.tagsArray.isEmpty {
                        tagsSection
                    }

                    // Linked Areas & Lessons
                    if !linkedAreaSet.isEmpty || !linkedLessons.isEmpty {
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
            .inlineNavigationTitle()
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

                            Button {
                                printResource()
                            } label: {
                                Label("Print", systemImage: "printer")
                            }
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
            .confirmationDialog("Delete CDResource?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
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
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
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
                .background(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
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
                Text(resource.createdAt ?? Date(), style: .date)
            }

            if resource.modifiedAt != resource.createdAt {
                metadataRow(label: "Modified", icon: "pencil") {
                    Text(resource.modifiedAt ?? Date(), style: .date)
                }
            }
        }
    }

    private func metadataRow<Content: View>(
        label: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
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
                ForEach(resource.tagsArray, id: \.self) { tag in
                    TagBadge(tag: tag)
                }
            }
        }
    }

    // MARK: - Linked Areas & Lessons

    private var linkingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !linkedAreaSet.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Linked Areas")
                        .font(.headline)

                    FlowLayout(spacing: 8) {
                        ForEach(linkedAreaSet, id: \.self) { area in
                            Text(area)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
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

                    ForEach(linkedLessons, id: \.objectID) { lesson in
                        HStack(spacing: 8) {
                            Image(systemName: "book")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(lesson.name)
                                .font(.subheadline)
                            if !lesson.area.isEmpty {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(lesson.area)
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

                Section("Notes") {
                    TextField("Description or usage notes", text: $editDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Organization") {
                    NavigationLink {
                        ResourceTagPicker(selectedTags: $editTags)
                    } label: {
                        HStack {
                            Label("Tags", systemImage: "tag")
                            Spacer()
                            if editTags.isEmpty {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(editTags.count) tag\(editTags.count == 1 ? "" : "s")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        ResourceAreaPicker(
                            availableAreas: availableAreas,
                            selectedAreas: $editAreas
                        )
                    } label: {
                        HStack {
                            Label("Areas", systemImage: "graduationcap")
                            Spacer()
                            if editAreas.isEmpty {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(editAreas.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        ResourceLessonPicker(
                            allLessons: Array(allLessons),
                            selectedLessonIDs: $editLessonIDs
                        )
                    } label: {
                        HStack {
                            Label("Lessons", systemImage: "book")
                            Spacer()
                            if editLessonIDs.isEmpty {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(editLessonIDs.count) linked")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit CDResource")
            .inlineNavigationTitle()
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
        viewContext.safeSave()
    }

    private func startEditing() {
        editTitle = resource.title
        editCategory = resource.category
        editDescription = resource.descriptionText
        editTags = resource.tagsArray
        editLessonIDs = linkedLessonIDSet
        editAreas = Set(linkedAreaSet)
        isEditing = true
    }

    private func saveEdits() {
        resource.title = editTitle.trimmingCharacters(in: .whitespaces)
        resource.category = editCategory
        resource.descriptionText = editDescription.trimmingCharacters(in: .whitespaces)
        resource.tagsArray = editTags
        resource.linkedLessonIDs = editLessonIDs.map(\.uuidString).sorted().joined(separator: ",")
        resource.linkedAreas = editAreas.sorted().joined(separator: ",")
        resource.modifiedAt = Date()
        viewContext.safeSave()
        isEditing = false
    }

    private func openInDefaultApp() {
        ResourceDocumentActions.open(resource)
    }

    private func printResource() {
        ResourceDocumentActions.print(resource)
    }

    private func deleteResource() {
        viewContext.delete(resource)
        viewContext.safeSave()
        dismiss()
    }
}
