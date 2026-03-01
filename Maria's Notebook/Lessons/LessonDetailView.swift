import OSLog
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct LessonDetailView: View {
    private static let logger = Logger.lessons
    var lesson: Lesson
    var onSave: (Lesson) -> Void
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    private var repository: LessonRepository {
        LessonRepository(context: modelContext, saveCoordinator: saveCoordinator)
    }

    @State private var isEditing = false
    @State private var draftName: String = ""
    @State private var draftSubject: String = ""
    @State private var draftGroup: String = ""
    @State private var draftSubheading: String = ""
    @State private var draftWriteUp: String = ""
    @State private var draftSuggestedFollowUpWork: String = ""
    @State private var draftSource: LessonSource = .album
    @State private var draftPersonalKind: PersonalLessonKind = .personal
    @State private var draftMaterials: String = ""
    @State private var draftPurpose: String = ""
    @State private var draftAgeRange: String = ""
    @State private var draftTeacherNotes: String = ""
    @State private var showDeleteAlert = false
    @State private var showingExerciseEditor = false
    @State private var editingExercise: LessonExercise? = nil

    @State private var showingPagesImporter = false
    @State private var resolvedPagesURL: URL?
    @State private var importError: String?
    @State private var previousManagedURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Lesson Info")
                    .font(AppTheme.ScaledFont.titleSmall)
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.top, AppTheme.Spacing.medium + 2)

            Divider()
                .padding(.top, AppTheme.Spacing.small)

            ScrollView {
                VStack(spacing: AppTheme.Spacing.xxl) {
                    headerContent
                        .padding(.top, AppTheme.Spacing.xlarge + 4)

                    if isEditing {
                        editForm
                    } else {
                        infoSection
                        
                        // Attachments Section
                        LessonAttachmentsSection(lesson: lesson)
                            .padding(.top, AppTheme.Spacing.small)
                        
                        // Journey Timeline
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                            Text("Lesson Journey")
                                .font(AppTheme.ScaledFont.titleSmall)

                            LessonJourneyTimeline(lesson: lesson, modelContext: modelContext)
                                .frame(height: 350)
                        }
                        .padding(.top, AppTheme.Spacing.large - 4)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xlarge)
                .padding(.bottom, AppTheme.Spacing.large)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .alert("Delete Lesson?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let url = resolveLessonFileURL() {
                    do {
                        try LessonFileStorage.deleteIfManaged(url)
                    } catch {
                        Self.logger.warning("Failed to delete managed file: \(error)")
                    }
                }
                do {
                    try repository.deleteLesson(id: lesson.id)
                } catch {
                    Self.logger.warning("Failed to delete lesson: \(error)")
                }
                if let onDone { onDone() } else { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear {
            seedDrafts()
            resolvedPagesURL = resolveLessonFileURL()
            if let url = resolvedPagesURL, LessonFileStorage.isManagedURL(url) {
                previousManagedURL = url
            }
            migrateLegacyLinkedFileIfNeeded()
        }
        .fileImporter(
            isPresented: $showingPagesImporter,
            allowedContentTypes: [UTType(filenameExtension: "pages")!]
        ) { result in
            switch result {
            case .success(let pickedURL):
                Task(priority: .userInitiated) {
                    let needsAccess = pickedURL.startAccessingSecurityScopedResource()
                    defer { if needsAccess { pickedURL.stopAccessingSecurityScopedResource() } }
                    do {
                        let destURL = try LessonFileStorage.importFile(from: pickedURL, forLessonWithID: lesson.id, lessonName: lesson.name)
                        let bookmark = try LessonFileStorage.makeBookmark(for: destURL)
                        let rel = try LessonFileStorage.relativePath(forManagedURL: destURL)
                        if let oldURL = previousManagedURL {
                            do {
                                try LessonFileStorage.deleteIfManaged(oldURL)
                            } catch {
                                Self.logger.warning("Failed to delete old managed file: \(error)")
                            }
                        }
                        await MainActor.run {
                            lesson.pagesFileBookmark = bookmark
                            lesson.pagesFileRelativePath = rel
                            resolvedPagesURL = destURL
                            previousManagedURL = destURL
                            _ = saveCoordinator.save(modelContext, reason: "Import lesson Pages file")
                        }
                    } catch {
                        await MainActor.run { importError = error.localizedDescription }
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    importError = error.localizedDescription
                }
            }
        }
        .alert("Import Failed", isPresented: Binding(get: {
            importError != nil
        }, set: { newValue in
            if !newValue {
                importError = nil
            }
        })) {
            Button("OK", role: .cancel) {
                importError = nil
            }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Subviews
    private var headerContent: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                .font(AppTheme.ScaledFont.titleXLarge)
                .frame(maxWidth: .infinity)
            HStack(spacing: AppTheme.Spacing.small) {
                if !lesson.subject.isEmpty {
                    StatusPill(text: lesson.subject, color: .accentColor, icon: nil)
                }
                if !lesson.group.isEmpty {
                    StatusPill(text: lesson.group, color: .accentColor, icon: nil)
                }
                if lesson.source == .personal {
                    StatusPill(text: lesson.personalKind?.badgeLabel ?? "Personal", color: .primary, icon: nil)
                }
                if lesson.source == .album {
                    StatusPill(text: "Album", color: .blue, icon: nil)
                }
                if !lesson.ageRange.isEmpty {
                    StatusPill(text: lesson.ageRange, color: .orange, icon: nil)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            infoRow(icon: SFSymbol.Education.bookClosed, title: "Name", value: lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
            infoRow(icon: SFSymbol.Education.graduationcap, title: "Subject", value: lesson.subject.isEmpty ? "—" : lesson.subject)
            infoRow(icon: SFSymbol.List.squareGrid, title: "Group", value: lesson.group.isEmpty ? "—" : lesson.group)
            infoRow(icon: "text.bubble", title: "Subheading", value: lesson.subheading.isEmpty ? "—" : lesson.subheading)
            infoRow(icon: "square.stack.3d.up", title: "Source", value: lesson.source.label)
            if lesson.source == .personal {
                infoRow(icon: SFSymbol.People.person, title: "Personal Type", value: lesson.personalKind?.label ?? "Personal")
            }
            if !lesson.ageRange.isEmpty {
                infoRow(icon: "person.2", title: "Age Range", value: lesson.ageRange)
            }

            // Purpose
            if !lesson.purpose.trimmed().isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                    HStack(spacing: AppTheme.Spacing.small + 2) {
                        Image(systemName: "target")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Purpose")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    Text(lesson.purpose)
                        .font(AppTheme.ScaledFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, AppTheme.Spacing.verySmall)
            }

            // Materials
            if !lesson.materialsItems.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                    HStack(spacing: AppTheme.Spacing.small + 2) {
                        Image(systemName: "tray.full")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Materials")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                        ForEach(lesson.materialsItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                                Text("•").font(AppTheme.ScaledFont.body)
                                Text(item)
                                    .font(AppTheme.ScaledFont.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.top, AppTheme.Spacing.verySmall)
            }

            // Write Up (Presentation Notes)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                HStack(spacing: AppTheme.Spacing.small + 2) {
                    Image(systemName: SFSymbol.Document.docText)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Presentation Notes")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                }
                if lesson.writeUp.trimmed().isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(lesson.writeUp)
                        .font(AppTheme.ScaledFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, AppTheme.Spacing.verySmall)

            // Teacher Notes
            if !lesson.teacherNotes.trimmed().isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                    HStack(spacing: AppTheme.Spacing.small + 2) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Teacher Notes")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    Text(lesson.teacherNotes)
                        .font(AppTheme.ScaledFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, AppTheme.Spacing.verySmall)
            }

            // Exercises
            if !lesson.sortedExercises.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        ForEach(lesson.sortedExercises) { exercise in
                            LessonExerciseRow(exercise: exercise)
                        }
                    }
                    .padding(.top, AppTheme.Spacing.xsmall)
                } label: {
                    HStack(spacing: AppTheme.Spacing.small + 2) {
                        Image(systemName: "list.number")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Exercises (\(lesson.sortedExercises.count))")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, AppTheme.Spacing.verySmall)
            }

            // Suggested Follow-Up Work
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                HStack(spacing: AppTheme.Spacing.small + 2) {
                    Image(systemName: SFSymbol.Action.checkmarkCircle)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Suggested Follow-Up Work")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                }
                if lesson.suggestedFollowUpWorkItems.isEmpty {
                    Text("No suggestions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                        ForEach(lesson.suggestedFollowUpWorkItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                                Text("•").font(AppTheme.ScaledFont.body)
                                Text(item)
                                    .font(AppTheme.ScaledFont.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(.top, AppTheme.Spacing.verySmall)

            // Prerequisites
            if !lesson.prerequisiteLessonUUIDs.isEmpty {
                LessonRelationshipsSection(
                    title: "Prerequisites",
                    icon: "arrow.backward.circle",
                    lessonIDs: lesson.prerequisiteLessonUUIDs,
                    modelContext: modelContext
                )
            }

            // Related Lessons
            if !lesson.relatedLessonUUIDs.isEmpty {
                LessonRelationshipsSection(
                    title: "Related Lessons",
                    icon: "link",
                    lessonIDs: lesson.relatedLessonUUIDs,
                    modelContext: modelContext
                )
            }

            if let url = resolvedPagesURL {
                HStack { Spacer() }
                OpenInPagesButton(title: "Open in Pages") { openInPages(url) }
                    .padding(.vertical, AppTheme.Spacing.small)
                HStack { Spacer() }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }

    private var editForm: some View {
        VStack(spacing: AppTheme.Spacing.compact + 2) {
            TextField("Lesson Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Subject", text: $draftSubject)
                    .textFieldStyle(.roundedBorder)
                TextField("Group", text: $draftGroup)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("Subheading", text: $draftSubheading)
                .textFieldStyle(.roundedBorder)

            Picker("Source", selection: $draftSource) {
                ForEach(LessonSource.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            if draftSource == .personal {
                Picker("Personal Type", selection: $draftPersonalKind) {
                    ForEach(PersonalLessonKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
            }

            TextField("Age Range (e.g., 6+, 3-6)", text: $draftAgeRange)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Purpose / Learning Objective")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftPurpose)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Materials")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                Text("Enter one material per line")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                TextEditor(text: $draftMaterials)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Imported Pages File")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        if resolvedPagesURL != nil {
                            Button("Remove") {
                                if let url = resolvedPagesURL {
                                    do {
                                        try LessonFileStorage.deleteIfManaged(url)
                                    } catch {
                                        Self.logger.warning("Failed to delete managed file: \(error)")
                                    }
                                }
                                lesson.pagesFileBookmark = nil
                                lesson.pagesFileRelativePath = nil
                                resolvedPagesURL = nil
                                previousManagedURL = nil
                                _ = saveCoordinator.save(modelContext, reason: "Remove lesson Pages file")
                            }
                        }
                        Button("Import…") { showingPagesImporter = true }
                    }
                    if let url = resolvedPagesURL {
                        OpenInPagesButton(title: "Open in Pages") { openInPages(url) }
                            .padding(.top, AppTheme.Spacing.xsmall)
                    } else {
                        Text("No file selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Notes")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftWriteUp)
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Teacher Notes")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftTeacherNotes)
                    .frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Suggested Follow-Up Work")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                Text("Enter one suggestion per line")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                TextEditor(text: $draftSuggestedFollowUpWork)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))
            }

            // Exercises Editor
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                HStack {
                    Text("Exercises")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editingExercise = nil
                        showingExerciseEditor = true
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if lesson.sortedExercises.isEmpty {
                    Text("No exercises yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lesson.sortedExercises) { exercise in
                        LessonExerciseRow(exercise: exercise)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingExercise = exercise
                                showingExerciseEditor = true
                            }
                    }
                }
            }
            .sheet(isPresented: $showingExerciseEditor) {
                LessonExerciseEditorSheet(
                    lesson: lesson,
                    existingExercise: editingExercise,
                    onSave: {}
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: AppTheme.Spacing.small + 2) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(AppTheme.ScaledFont.titleSmall)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                if isEditing {
                    Button("Cancel") { isEditing = false }
                    Button("Save") {
                        let updated = lesson
                        updated.name = draftName.trimmed()
                        updated.subject = draftSubject.trimmed()
                        updated.group = draftGroup.trimmed()
                        updated.subheading = draftSubheading.trimmed()
                        updated.writeUp = draftWriteUp
                        updated.suggestedFollowUpWork = draftSuggestedFollowUpWork
                        updated.source = draftSource
                        if draftSource == .personal {
                            updated.personalKind = draftPersonalKind
                        } else {
                            updated.personalKind = nil
                        }
                        updated.materials = draftMaterials
                        updated.purpose = draftPurpose.trimmed()
                        updated.ageRange = draftAgeRange.trimmed()
                        updated.teacherNotes = draftTeacherNotes
                        onSave(updated)
                        isEditing = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmed().isEmpty)
                } else {
                    Button("Edit") {
                        seedDrafts()
                        isEditing = true
                    }
                    Button("Delete", role: .destructive) {
                        showDeleteAlert = true
                    }
                    Button("Done") {
                        if let onDone { onDone() } else { dismiss() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.large - 4)
            .padding(.vertical, AppTheme.Spacing.compact)
            .background(.bar)
        }
    }

    private func seedDrafts() {
        draftName = lesson.name
        draftSubject = lesson.subject
        draftGroup = lesson.group
        draftSubheading = lesson.subheading
        draftWriteUp = lesson.writeUp
        draftSuggestedFollowUpWork = lesson.suggestedFollowUpWork
        draftSource = lesson.source
        draftPersonalKind = lesson.personalKind ?? .personal
        draftMaterials = lesson.materials
        draftPurpose = lesson.purpose
        draftAgeRange = lesson.ageRange
        draftTeacherNotes = lesson.teacherNotes
    }

    private func resolvePagesURL() -> URL? {
        guard let bookmarkData = lesson.pagesFileBookmark else {
            return nil
        }

        var isStale = false
        do {
#if os(macOS)
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI, .withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
#else
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
#endif

#if os(iOS)
            if url.startAccessingSecurityScopedResource() {
                // Caller must call stopAccessingSecurityScopedResource when done, but here we keep it open as long as resolvedPagesURL is set
                // So keep it open; will be released when resolvedPagesURL changes or view disappears
            }
#endif

            if isStale {
                // Optionally recreate bookmark here
                savePagesBookmark(from: url)
            }
            return url
        } catch {
            return nil
        }
    }

    private func resolveLessonFileURL() -> URL? {
        if let rel = lesson.pagesFileRelativePath, !rel.isEmpty {
            do {
                return try LessonFileStorage.resolve(relativePath: rel)
            } catch {
                Self.logger.warning("Failed to resolve relative path: \(error)")
            }
        }
        return resolvePagesURL()
    }

    private func migrateLegacyLinkedFileIfNeeded() {
        guard lesson.pagesFileRelativePath == nil, lesson.pagesFileBookmark != nil else { return }
        guard let legacyURL = resolvePagesURL(), !LessonFileStorage.isManagedURL(legacyURL) else { return }
        Task(priority: .utility) {
            do {
                let destURL = try LessonFileStorage.importFile(from: legacyURL, forLessonWithID: lesson.id, lessonName: lesson.name)
                let bookmark = try LessonFileStorage.makeBookmark(for: destURL)
                let rel = try LessonFileStorage.relativePath(forManagedURL: destURL)
                await MainActor.run {
                    lesson.pagesFileBookmark = bookmark
                    lesson.pagesFileRelativePath = rel
                    resolvedPagesURL = destURL
                    previousManagedURL = destURL
                    _ = saveCoordinator.save(modelContext, reason: "Migrate lesson file to managed storage")
                }
            } catch {
                await MainActor.run { importError = error.localizedDescription }
            }
        }
    }

    private func savePagesBookmark(from url: URL) {
#if os(iOS)
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            lesson.pagesFileBookmark = bookmark
        } catch {
            // ignore error
        }
#elseif os(macOS)
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            lesson.pagesFileBookmark = bookmark
        } catch {
            // ignore error
        }
#endif
    }

    private func openInPages(_ url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        #if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #elseif os(macOS)
        if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: pagesAppURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

struct OpenInPagesButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.ScaledFont.bodySemibold)
                .padding(.horizontal, AppTheme.Spacing.large - 4)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                        .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    let container = ModelContainer.preview
    let ctx = container.mainContext
    let lesson = Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Intro to base-10", writeUp: "Sample write up.")
    ctx.insert(lesson)
    return LessonDetailView(lesson: lesson, onSave: { _ in })
        .previewEnvironment(using: container)
}

