import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#endif

struct LessonDetailCard: View {
    static let logger = Logger.lessons

    var lesson: Lesson
    var onSave: (Lesson) -> Void
    var onClose: () -> Void
    var onGiveLesson: ((Lesson) -> Void)?
    var initialMode: LessonDetailInitialMode = .normal

    @Environment(\.modelContext) var modelContext
    @Environment(SaveCoordinator.self) var saveCoordinator

    @State var isEditing = false
    @State var draftName: String = ""
    @State var draftSubject: String = ""
    @State var draftGroup: String = ""
    @State var draftSubheading: String = ""
    @State var draftWriteUp: String = ""
    @State var draftSuggestedFollowUpWork: String = ""
    @State var showDeleteAlert = false

    @State var draftSource: LessonSource = .album
    @State var draftPersonalKind: PersonalLessonKind = .personal
    @State var draftMaterials: String = ""
    @State var draftPurpose: String = ""
    @State var draftAgeRange: String = ""
    @State var draftTeacherNotes: String = ""
    @State var draftLessonFormat: LessonFormat = .standard
    @State var draftParentStoryID: UUID?
    @State var showingSampleWorkEditor = false
    @State var editingSampleWork: SampleWork?

    @State var showingPagesImporter = false
    @State var resolvedPagesURL: URL?
    @State var importError: String?
    @State var previousManagedURL: URL?

#if canImport(UniformTypeIdentifiers)
    var pagesAllowedTypes: [UTType] {
        var set: Set<UTType> = []
        if let t = UTType("com.apple.iwork.pages.sffpages") { set.insert(t) }
        if let t2 = UTType(filenameExtension: "pages") { set.insert(t2) }
        set.insert(.package)
        set.insert(.data)
        set.insert(.content)
        set.insert(.item)
        return Array(set)
    }
#endif

    var body: some View {
        VStack(spacing: 16) {
            headerBar

            titleAndBadges

            Divider()
                .padding(.vertical, 4)

            if isEditing {
                editForm
            } else {
                infoSection
            }

            Divider()
                .padding(.top, 4)

            bottomBar
        }
        .padding(16)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 10)
        )
        .onAppear {
            seedDrafts()
            if initialMode == .giveLesson {
                onGiveLesson?(lesson)
            }
            resolvedPagesURL = resolveLessonFileURL()
            if let url = resolvedPagesURL, LessonFileStorage.isManagedURL(url) {
                previousManagedURL = url
            }
            migrateLegacyLinkedFileIfNeeded()
        }
        .alert("Delete Lesson?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(lesson)
                saveCoordinator.save(modelContext, reason: "Delete lesson")
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .fileImporter(
            isPresented: $showingPagesImporter,
            allowedContentTypes: pagesAllowedTypes
        ) { result in
            handleFileImporterResult(result)
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .accessibilityElement(children: .combine)
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
        draftLessonFormat = lesson.lessonFormat
        draftParentStoryID = lesson.parentStoryUUID
    }

    private func handleFileImporterResult(_ result: Result<URL, Error>) {
        do {
            let pickedURL = try result.get()
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
                        saveCoordinator.save(modelContext, reason: "Import lesson Pages file")
                    }
                } catch {
                    await MainActor.run { importError = error.localizedDescription }
                }
            }
        } catch {
            Task { @MainActor in
                importError = error.localizedDescription
            }
        }
    }
}

#Preview {
    let container = ModelContainer.preview
    let ctx = container.mainContext
    let lesson = Lesson(
        name: "Decimal System", subject: "Math", group: "Number Work",
        subheading: "Intro to base-10", writeUp: "A foundational presentation."
    )
    ctx.insert(lesson)
    return LessonDetailCard(lesson: lesson, onSave: { _ in }, onClose: {})
        .previewEnvironment(using: container)
}
