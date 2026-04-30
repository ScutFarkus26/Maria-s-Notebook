import SwiftUI
@preconcurrency import PDFKit
import CoreData
import OSLog

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct StoryDetailView: View {
    @ObservedObject var story: CDStory
    @Environment(\.managedObjectContext) private var viewContext
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var newThemeText: String = ""
    @State private var showingDeleteConfirm = false
    @State private var isGeneratingCover = false
    @State private var coverGenerationError: String?
    @State private var isFindingConnections = false
    @State private var connectionsError: String?

    private static let logger = Logger.stories

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroImageSection
                    coverActionsRow
                    if !story.analysisErrorMessage.isEmpty {
                        statusBanner
                    }
                    titleSection
                    gradeSection
                    themesSection
                    summarySection
                    connectedLessonsSection
                    actionButtons
                }
                .padding(16)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(story.displayTitle)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Sections

    /// Shows the generated AI cover when available, otherwise falls back to the
    /// PDF first-page render.
    @ViewBuilder
    private var heroImageSection: some View {
        if isGeneratingCover {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Generating cover…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let coverData = story.generatedCoverData,
                  let image = platformImage(from: coverData) {
            heroImage(image, label: "AI cover")
        } else if let thumbnailData = story.thumbnailData,
                  let image = platformImage(from: thumbnailData) {
            heroImage(image, label: nil)
        }
    }

    @ViewBuilder
    private func heroImage(_ image: PlatformImage, label: String?) -> some View {
        ZStack(alignment: .topTrailing) {
            #if os(macOS)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            #else
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            #endif
            if let label {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var coverActionsRow: some View {
        if StoryCoverGenerator.isAvailable {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if story.generatedCoverData == nil {
                        Button {
                            generateCover()
                        } label: {
                            Label("Generate Cover", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratingCover)
                    } else {
                        Button {
                            generateCover()
                        } label: {
                            Label("Regenerate Cover", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratingCover)

                        Button(role: .destructive) {
                            removeCover()
                        } label: {
                            Label("Remove Cover", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratingCover)
                    }
                    Spacer(minLength: 0)
                }
                providerHint
                if let message = coverGenerationError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var providerHint: some View {
        switch StoryCoverGenerator.provider {
        case .openAI:
            let claudeHint = AnthropicAPIClient.hasAPIKey() ? " · Claude refines the prompt" : ""
            Text("Using OpenAI gpt-image-1\(claudeHint)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .imagePlayground:
            Text("Using Apple Image Playground · add an OpenAI key in Settings for higher-quality covers")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }

    private var statusBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: story.analysisStatus == .manual ? "pencil" : "exclamationmark.triangle")
                .foregroundStyle(story.analysisStatus == .manual ? .orange : .red)
            Text(story.analysisErrorMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Title", text: titleBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveContext() }
        }
    }

    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grade Level")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Picker("From", selection: gradeMinBinding) {
                    Text("—").tag(StoryGrade?.none)
                    ForEach(StoryGrade.allCases) { grade in
                        Text(grade.longLabel).tag(StoryGrade?.some(grade))
                    }
                }
                .labelsHidden()
                Text("to")
                    .foregroundStyle(.secondary)
                Picker("To", selection: gradeMaxBinding) {
                    Text("—").tag(StoryGrade?.none)
                    ForEach(StoryGrade.allCases) { grade in
                        Text(grade.longLabel).tag(StoryGrade?.some(grade))
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Themes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(story.themesArray, id: \.self) { theme in
                    StoryThemeChip(theme, variant: .removable {
                        removeTheme(theme)
                    })
                }
            }
            HStack {
                TextField("Add theme", text: $newThemeText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTheme() }
                Button("Add") {
                    addTheme()
                }
                .disabled(newThemeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Summary")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: summaryBinding)
                .frame(minHeight: 80)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Connected Lessons

    private var connectedLessonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Connected Lessons")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    findConnections()
                } label: {
                    if isFindingConnections {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Finding…")
                        }
                    } else {
                        let label = story.relatedLessonUUIDs.isEmpty ? "Find" : "Refresh"
                        let icon = story.relatedLessonUUIDs.isEmpty ? "wand.and.stars" : "arrow.clockwise"
                        Label(label, systemImage: icon)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(isFindingConnections)
            }

            connectedLessonsList

            if let analyzedAt = story.relatedLessonsAnalyzedAt,
               !story.relatedLessonUUIDs.isEmpty {
                Text("Analyzed \(analyzedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !AnthropicAPIClient.hasAPIKey() {
                Text("Add a Claude API key in Settings for explanations of each match.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let error = connectionsError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var connectedLessonsList: some View {
        let entries = story.loadRelatedLessons(in: viewContext)
        if entries.isEmpty {
            Text("No connections found yet. Tap Find to analyze your lesson library.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            VStack(spacing: 6) {
                ForEach(entries, id: \.lesson.objectID) { entry in
                    connectedLessonRow(entry: entry)
                }
            }
        }
    }

    private func connectedLessonRow(entry: (lesson: CDLesson, reason: String)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.lesson.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if !entry.lesson.subject.isEmpty {
                    let subjectColor = AppColors.color(forSubject: entry.lesson.subject)
                    Text(entry.lesson.subject)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(subjectColor.opacity(0.18)))
                        .foregroundStyle(subjectColor)
                }
                Spacer(minLength: 0)
            }
            if !entry.reason.isEmpty {
                Text(entry.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    openPDF()
                } label: {
                    Label("Open PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)
                if StoryAnalyzer.isAIEnabled && story.analysisStatus != .manual {
                    Button {
                        StoryImportService.reanalyze(story: story, context: viewContext)
                    } label: {
                        Label("Re-extract with AI", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .disabled(story.analysisStatus == .analyzing)
                }
                Spacer()
            }
            HStack {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Story", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .confirmationDialog(
            "Delete this story?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteStory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the story and its PDF file. This can't be undone.")
        }
    }

    // MARK: - Bindings

    private var titleBinding: Binding<String> {
        Binding(
            get: { story.title },
            set: { newValue in
                let trimmed = newValue
                if story.title != trimmed {
                    story.title = trimmed
                    story.userEditedTitle = !trimmed.isEmpty
                    story.modifiedAt = Date()
                    saveContext()
                }
            }
        )
    }

    private var summaryBinding: Binding<String> {
        Binding(
            get: { story.summary },
            set: { newValue in
                if story.summary != newValue {
                    story.summary = newValue
                    story.modifiedAt = Date()
                    saveContext()
                }
            }
        )
    }

    private var gradeMinBinding: Binding<StoryGrade?> {
        Binding(
            get: { story.gradeMin },
            set: { newValue in
                story.gradeMin = newValue
                if let max = story.gradeMax, let min = newValue, min.ordinal > max.ordinal {
                    story.gradeMax = min
                }
                story.modifiedAt = Date()
                saveContext()
            }
        )
    }

    private var gradeMaxBinding: Binding<StoryGrade?> {
        Binding(
            get: { story.gradeMax },
            set: { newValue in
                story.gradeMax = newValue
                if let min = story.gradeMin, let max = newValue, max.ordinal < min.ordinal {
                    story.gradeMin = max
                }
                story.modifiedAt = Date()
                saveContext()
            }
        )
    }

    // MARK: - Actions

    private func addTheme() {
        let candidate = newThemeText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !candidate.isEmpty else { return }
        var current = story.themesArray
        if !current.contains(where: { $0.lowercased() == candidate }) {
            current.append(candidate)
            story.themesArray = current
            story.userEditedThemes = true
            story.modifiedAt = Date()
            saveContext()
        }
        newThemeText = ""
    }

    private func removeTheme(_ theme: String) {
        let target = theme.lowercased()
        var current = story.themesArray
        current.removeAll { $0.lowercased() == target }
        story.themesArray = current
        story.userEditedThemes = true
        story.modifiedAt = Date()
        saveContext()
    }

    private func generateCover() {
        guard !isGeneratingCover else { return }
        coverGenerationError = nil
        isGeneratingCover = true

        let title = story.title
        let themes = story.themesArray
        let summary = story.summary
        let objectID = story.objectID
        let context = viewContext

        Task { @MainActor in
            defer { isGeneratingCover = false }
            do {
                let data = try await StoryCoverGenerator.generateCover(
                    title: title,
                    themes: themes,
                    summary: summary
                )
                if let target = try? context.existingObject(with: objectID) as? CDStory {
                    target.generatedCoverData = data
                    target.modifiedAt = Date()
                    if !context.safeSave() {
                        Self.logger.warning("Failed to save generated cover")
                    }
                }
            } catch let error as StoryCoverGeneratorError {
                coverGenerationError = error.errorDescription
            } catch {
                coverGenerationError = error.localizedDescription
            }
        }
    }

    private func removeCover() {
        story.generatedCoverData = nil
        story.modifiedAt = Date()
        saveContext()
    }

    private func findConnections() {
        guard !isFindingConnections else { return }
        connectionsError = nil
        isFindingConnections = true

        let objectID = story.objectID
        let context = viewContext

        Task { @MainActor in
            defer { isFindingConnections = false }
            do {
                guard let target = try? context.existingObject(with: objectID) as? CDStory else {
                    return
                }
                let matches = try await StoryLessonMatcher.findConnections(
                    for: target,
                    in: context
                )
                target.storeRelatedLessons(matches.map { ($0.lessonID, $0.reason) })
                if !context.safeSave() {
                    Self.logger.warning("Failed to save related lessons")
                }
            } catch let error as StoryLessonMatcher.MatcherError {
                connectionsError = error.errorDescription
            } catch {
                connectionsError = error.localizedDescription
            }
        }
    }

    private func openPDF() {
        guard let url = StoryFileStorage.resolveURL(
            bookmark: story.pdfFileBookmark,
            relativePath: story.pdfFileRelativePath
        ) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        // On iOS, open via the system. Caller can route to a Quick Look sheet.
        UIApplication.shared.open(url)
        #endif
    }

    private func deleteStory() {
        if let url = StoryFileStorage.resolveURL(
            bookmark: story.pdfFileBookmark,
            relativePath: story.pdfFileRelativePath
        ) {
            try? StoryFileStorage.deleteIfManaged(url)
        }
        viewContext.delete(story)
        saveContext()
        onDelete()
    }

    private func saveContext() {
        if !viewContext.safeSave() {
            Self.logger.warning("Failed to save story changes")
        }
    }

    private func platformImage(from data: Data) -> PlatformImage? {
        PlatformImage(data: data)
    }
}
