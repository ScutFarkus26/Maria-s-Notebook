import OSLog
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
import CoreData
#endif

/// A lesson's card: its details, files and journey, with Edit and Delete.
///
/// The card saves its own edits through `SaveCoordinator`, so every host (the
/// Lessons pane, the Mac lesson window, the Parsha pages) gets the same Save;
/// `onSave` is only told afterwards. The Mac window and the Parsha pages once
/// passed an empty `onSave` and their edits were never saved (bug hunt
/// 2026-10-10, #38).
struct LessonDetailView: View {
    static let logger = Logger.lessons
    var lesson: CDLesson
    var allLessons: [CDLesson] = []
    /// Called after the card has saved an edit.
    var onSave: ((CDLesson) -> Void)?
    var onDone: (() -> Void)?
    var onLocateInMap: ((CDLesson) -> Void)?
    var onSchedule: ((CDLesson) -> Void)?

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.managedObjectContext) var managedObjectContext
    @Environment(SaveCoordinator.self) var saveCoordinator
    /// The Sample Class's lessons point at the real notebook's files, so there
    /// its file actions change records only.
    @Environment(\.isSampleClassroom) var isSampleClassroom

    var repository: LessonRepository {
        LessonRepository(context: managedObjectContext, saveCoordinator: saveCoordinator)
    }

    var existingAreas: [String] {
        Array(Set(allLessons.map { $0.area.trimmed() }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var existingSequences: [String] {
        let area = draft.area.trimmed()
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
        let area = draft.area.trimmed()
        let sequence = draft.sequence.trimmed()
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

    @State var isEditing = false
    /// The edit fields, tied to the lesson they were filled from.
    @State var draft = LessonEditDraft()
    /// Non-nil while the delete confirmation is up: what the delete takes with it.
    @State var pendingDeletion: LessonDeletionSummary?
    @State private var showingGreatLessonTagEditor = false
    @State var showingSampleWorkEditor = false
    @State var editingSampleWork: CDSampleWork?

    @State var showingPagesImporter = false
    @State var resolvedPagesURL: URL?
    @State var importError: String?
    @State var deleteError: String?
    /// Non-nil while Save is refused: the lesson's sub-area already has one by
    /// that name (`LessonRepository.CreationError`, Add Lesson's wording).
    @State var saveRefusal: String?
    /// Shown when a file can't be added in the Sample Class.
    @State var showingSampleClassFileNotice = false

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar: close, spacer, open-in-new-window
            HStack(spacing: 8) {
                Button {
                    close()
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
        // Handoff: the same lesson on the guide's other devices.
        .userActivity(Handoff.ActivityType.lesson, element: lesson.id) { id, activity in
            Handoff.describeLesson(activity, id: id, name: lesson.name)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .alert(
            "Delete Lesson?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { _ in
            Button("Delete", role: .destructive) { deleteLesson() }
            Button("Cancel", role: .cancel) {}
        } message: { summary in
            Text(summary.message(trashesFiles: !isSampleClassroom))
        }
        .alert("Couldn't Delete the Lesson", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .alert(
            AppErrorMessages.Lessons.alreadyFiledTitle,
            isPresented: Binding(
                get: { saveRefusal != nil },
                set: { if !$0 { saveRefusal = nil } }
            ),
            presenting: saveRefusal
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { refusal in
            Text(refusal)
        }
        .alert(LessonAttachmentsSection.sampleClassFilesTitle, isPresented: $showingSampleClassFileNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LessonAttachmentsSection.sampleClassFilesMessage)
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
        }
        .fileImporter(
            isPresented: $showingPagesImporter,
            allowedContentTypes: [UTType(filenameExtension: "pages")!]
        ) { result in
            switch result {
            case .success(let pickedURL):
                Task(priority: .userInitiated) { importPagesFile(from: pickedURL) }
            case .failure(let error):
                Task {
                    importError = AppErrorMessages.importMessage(for: error, fileType: "Pages file")
                }
            }
        }
        .alert("Couldn't Add the Pages File", isPresented: Binding(get: {
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
                    Button("Save") { saveEdits() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.name.trimmed().isEmpty)
                } else {
                    if let onLocateInMap, !lesson.area.trimmed().isEmpty {
                        Button {
                            onLocateInMap(lesson)
                        } label: {
                            Label("Locate in Map", systemImage: "chart.bar.doc.horizontal")
                        }
                        .help("Show this lesson's thread in the scope-and-sequence map")
                    }
                    Button("Delete", role: .destructive) {
                        confirmDelete()
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
        draft = LessonEditDraft(lesson: lesson)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct LessonDetailViewPreview: View {
    var body: some View {
        let ctx = CoreDataStack.preview.viewContext
        let lesson = CDLesson(context: ctx)
        lesson.name = "Decimal System"
        lesson.area = "Math"
        lesson.sequence = "Number Work"
        lesson.section = "Intro to base-10"
        lesson.writeUp = "Sample write up."

        return LessonDetailView(lesson: lesson)
            .previewEnvironment()
    }
}

#Preview {
    LessonDetailViewPreview()
}
