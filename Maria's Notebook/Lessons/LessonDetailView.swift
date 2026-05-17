import OSLog
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
import CoreData
#endif

struct LessonDetailView: View {
    static let logger = Logger.lessons
    var lesson: CDLesson
    var allLessons: [CDLesson] = []
    var onSave: (CDLesson) -> Void
    var onDone: (() -> Void)?
    var onLocateInMap: ((CDLesson) -> Void)?
    var onLocateInSequence: ((CDLesson) -> Void)?
    var onSchedule: ((CDLesson) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.managedObjectContext) var managedObjectContext
    @Environment(SaveCoordinator.self) var saveCoordinator

    private var repository: LessonRepository {
        LessonRepository(context: managedObjectContext, saveCoordinator: saveCoordinator)
    }

    var existingAreas: [String] {
        Array(Set(allLessons.map { $0.area.trimmed() }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var existingSequences: [String] {
        let area = draftArea.trimmed()
        guard !area.isEmpty else { return [] }
        return Array(Set(
            allLessons
                .filter { $0.area.trimmed().caseInsensitiveCompare(area) == .orderedSame }
                .map { $0.sequence.trimmed() }
                .filter { !$0.isEmpty }
        ))
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var existingSections: [String] {
        let area = draftArea.trimmed()
        let sequence = draftSequence.trimmed()
        guard !area.isEmpty, !sequence.isEmpty else { return [] }
        return Array(Set(
            allLessons
                .filter {
                    $0.area.trimmed().caseInsensitiveCompare(area) == .orderedSame &&
                    $0.sequence.trimmed().caseInsensitiveCompare(sequence) == .orderedSame
                }
                .map { $0.section.trimmed() }
                .filter { !$0.isEmpty }
        ))
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @State private var isEditing = false
    @State var draftName: String = ""
    @State var draftArea: String = ""
    @State var draftSequence: String = ""
    @State var draftSection: String = ""
    @State var draftWriteUp: String = ""
    @State var draftSuggestedFollowUpWork: String = ""
    @State var draftSource: LessonSource = .album
    @State var draftPersonalKind: PersonalLessonKind = .personal
    @State var draftMaterials: String = ""
    @State var draftPurpose: String = ""
    @State var draftAgeRange: String = ""
    @State var draftTeacherNotes: String = ""
    @State var draftLessonFormat: LessonFormat = .standard
    @State var draftParentStoryID: UUID?
    @State var draftPracticeOverride: ProgressionOverride = .inherit
    @State var draftConfirmationOverride: ProgressionOverride = .inherit
    @State private var showDeleteAlert = false
    @State private var showingGreatLessonTagEditor = false
    @State var showingSampleWorkEditor = false
    @State var editingSampleWork: CDSampleWorkEntity?

    @State var showingPagesImporter = false
    @State var resolvedPagesURL: URL?
    @State var importError: String?
    @State var previousManagedURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar: close, spacer, open-in-new-window
            HStack(spacing: 8) {
                Button {
                    if let onDone { onDone() } else { dismiss() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
                .keyboardShortcut(.cancelAction)

                Spacer()

                #if os(macOS)
                Button {
                    if let id = lesson.id { openLessonInNewWindow(id) }
                } label: {
                    Image(systemName: "uiwindow.split.2x1")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in New Window")
                #endif
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.top, AppTheme.Spacing.small)
            .padding(.bottom, AppTheme.Spacing.xsmall)

            Divider()

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

                            LessonJourneyTimeline(lesson: lesson, viewContext: viewContext)
                                .frame(height: 350)
                        }
                        .padding(.top, AppTheme.Spacing.large - 4)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xlarge)
                .padding(.bottom, AppTheme.Spacing.large)
            }
        }
        .frame(minWidth: 440, minHeight: 560)
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
                    guard let lessonID = lesson.id else { return }
                    try repository.deleteLesson(id: lessonID)
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
                        guard let lessonID = lesson.id else { return }
                        let destURL = try LessonFileStorage.importFile(
                            from: pickedURL,
                            forLessonWithID: lessonID,
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
                            saveCoordinator.save(viewContext, reason: "Import lesson Pages file")
                        }
                    } catch {
                        await MainActor.run { importError = AppErrorMessages.importMessage(for: error, fileType: "lesson file") }
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    importError = AppErrorMessages.importMessage(for: error, fileType: "lesson file")
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
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack(spacing: AppTheme.Spacing.small) {
                if !lesson.area.isEmpty {
                    StatusPill(text: lesson.area, color: .accentColor, icon: nil)
                }
                if !lesson.sequence.isEmpty {
                    StatusPill(text: lesson.sequence, color: .accentColor, icon: nil)
                }
                if lesson.isStory {
                    StatusPill(text: "Story", color: .purple, icon: "book.pages")
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

            // Primary action: Give Lesson — the most common follow-up after viewing.
            if !isEditing, let onSchedule {
                Button {
                    onSchedule(lesson)
                } label: {
                    Label("Give Lesson", systemImage: "person.crop.circle.badge.checkmark")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, AppTheme.Spacing.xsmall)
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
                        updated.area = draftArea.trimmed()
                        updated.sequence = draftSequence.trimmed()
                        updated.section = draftSection.trimmed()
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
                        updated.lessonFormat = draftLessonFormat
                        updated.parentStoryUUID = draftLessonFormat == .story ? draftParentStoryID : nil
                        updated.practiceOverride = draftPracticeOverride
                        updated.confirmationOverride = draftConfirmationOverride
                        onSave(updated)
                        isEditing = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmed().isEmpty)
                } else {
                    if let onLocateInSequence, !lesson.area.trimmed().isEmpty {
                        Button {
                            onLocateInSequence(lesson)
                        } label: {
                            Label("Show in List", systemImage: "list.bullet.indent")
                        }
                        .help("Switch to the List view and focus on this lesson")
                    }
                    if let onLocateInMap, !lesson.area.trimmed().isEmpty {
                        Button {
                            onLocateInMap(lesson)
                        } label: {
                            Label("Locate in Map", systemImage: "chart.bar.doc.horizontal")
                        }
                        .help("Show this lesson's thread in the scope-and-sequence map")
                    }
                    Button("Delete", role: .destructive) {
                        showDeleteAlert = true
                    }
                    Button("Edit") {
                        seedDrafts()
                        isEditing = true
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
        draftArea = lesson.area
        draftSequence = lesson.sequence
        draftSection = lesson.section
        draftWriteUp = lesson.writeUp
        draftSuggestedFollowUpWork = lesson.suggestedFollowUpWork
        draftSource = lesson.source
        draftPersonalKind = lesson.personalKind ?? .personal
        draftMaterials = lesson.materials
        draftPurpose = lesson.purpose
        draftAgeRange = lesson.ageRange
        draftTeacherNotes = lesson.teacherNotes
        draftLessonFormat = lesson.lessonFormat
        draftParentStoryID = lesson.parentStoryUUID
        draftPracticeOverride = lesson.practiceOverride
        draftConfirmationOverride = lesson.confirmationOverride
    }
}

#Preview {
    let ctx = CoreDataStack.preview.viewContext
    let lesson = CDLesson(context: ctx)
    lesson.name = "Decimal System"
    lesson.area = "Math"
    lesson.sequence = "Number Work"
    lesson.section = "Intro to base-10"
    lesson.writeUp = "Sample write up."

    return LessonDetailView(lesson: lesson, onSave: { _ in })
        .previewEnvironment()
}
