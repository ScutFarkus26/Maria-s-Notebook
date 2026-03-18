import OSLog
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct LessonDetailView: View {
    static let logger = Logger.lessons
    var lesson: Lesson
    var allLessons: [Lesson] = []
    var onSave: (Lesson) -> Void
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var modelContext
    @Environment(SaveCoordinator.self) var saveCoordinator

    private var repository: LessonRepository {
        LessonRepository(context: modelContext, saveCoordinator: saveCoordinator)
    }

    var existingSubjects: [String] {
        Array(Set(allLessons.map { $0.subject.trimmed() }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var existingGroups: [String] {
        let subject = draftSubject.trimmed()
        guard !subject.isEmpty else { return [] }
        return Array(Set(
            allLessons
                .filter { $0.subject.trimmed().caseInsensitiveCompare(subject) == .orderedSame }
                .map { $0.group.trimmed() }
                .filter { !$0.isEmpty }
        ))
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var existingSubheadings: [String] {
        let subject = draftSubject.trimmed()
        let group = draftGroup.trimmed()
        guard !subject.isEmpty, !group.isEmpty else { return [] }
        return Array(Set(
            allLessons
                .filter {
                    $0.subject.trimmed().caseInsensitiveCompare(subject) == .orderedSame &&
                    $0.group.trimmed().caseInsensitiveCompare(group) == .orderedSame
                }
                .map { $0.subheading.trimmed() }
                .filter { !$0.isEmpty }
        ))
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @State private var isEditing = false
    @State var draftName: String = ""
    @State var draftSubject: String = ""
    @State var draftGroup: String = ""
    @State var draftSubheading: String = ""
    @State var draftWriteUp: String = ""
    @State var draftSuggestedFollowUpWork: String = ""
    @State var draftSource: LessonSource = .album
    @State var draftPersonalKind: PersonalLessonKind = .personal
    @State var draftMaterials: String = ""
    @State var draftPurpose: String = ""
    @State var draftAgeRange: String = ""
    @State var draftTeacherNotes: String = ""
    @State private var showDeleteAlert = false
    @State private var showingGreatLessonTagEditor = false
    @State var showingSampleWorkEditor = false
    @State var editingSampleWork: SampleWork?

    @State var showingPagesImporter = false
    @State var resolvedPagesURL: URL?
    @State var importError: String?
    @State var previousManagedURL: URL?

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
        .sheet(isPresented: $showingGreatLessonTagEditor) {
            NavigationStack {
                GreatLessonTagEditor(lesson: lesson)
                    .navigationTitle("Tag Great Lesson")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingGreatLessonTagEditor = false }
                        }
                    }
            }
            #if os(iOS)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            #else
            .frame(minWidth: 340, minHeight: 300)
            #endif
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
                        let destURL = try LessonFileStorage.importFile(
                            from: pickedURL,
                            forLessonWithID: lesson.id,
                            lessonName: lesson.name
                        )
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

}

// MARK: - Subviews

extension LessonDetailView {
    var headerContent: some View {
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
                if let gl = lesson.greatLesson {
                    StatusPill(text: gl.shortName, color: gl.color, icon: gl.icon)
                }
            }

            // Great Lesson tag button
            Button {
                showingGreatLessonTagEditor = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe.americas")
                        .font(.caption2)
                    Text(lesson.greatLesson != nil ? "Change Great Lesson" : "Tag Great Lesson")
                        .font(.caption)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    var bottomBar: some View {
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

    func seedDrafts() {
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
}

#Preview {
    let container = ModelContainer.preview
    let ctx = container.mainContext
    let lesson = Lesson(
        name: "Decimal System", subject: "Math", group: "Number Work",
        subheading: "Intro to base-10", writeUp: "Sample write up."
    )
    ctx.insert(lesson)
    return LessonDetailView(lesson: lesson, onSave: { _ in })
        .previewEnvironment(using: container)
}
