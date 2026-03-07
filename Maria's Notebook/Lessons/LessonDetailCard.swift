// swiftlint:disable file_length
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#endif

public enum LessonDetailInitialMode {
    case normal
    case giveLesson
}

// swiftlint:disable:next type_body_length
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
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(isEditing ? "Edit Lesson" : "Lesson Details")
                    .font(AppTheme.ScaledFont.titleSmall)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            // Title + badges
            VStack(spacing: 8) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(AppTheme.ScaledFont.titleLarge)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    if !lesson.subject.isEmpty {
                        Text(lesson.subject)
                            .font(AppTheme.ScaledFont.bodySemibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                    if !lesson.group.isEmpty {
                        Text(lesson.group)
                            .font(AppTheme.ScaledFont.bodySemibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                    if lesson.source == .personal {
                        Text(lesson.personalKind?.badgeLabel ?? "Personal")
                            .font(AppTheme.ScaledFont.bodySemibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    if !lesson.ageRange.isEmpty {
                        Text(lesson.ageRange)
                            .font(AppTheme.ScaledFont.bodySemibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }
            }
            .padding(.top, 4)

            Divider()
                .padding(.vertical, 4)

            if isEditing {
                editForm
            } else {
                infoSection
            }

            Divider()
                .padding(.top, 4)

            // Bottom bar (inline for card)
            HStack(spacing: 12) {
                Spacer()
                if isEditing {
                    Button {
                        isEditing = false
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button {
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
                    } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmed().isEmpty)
                } else {
                    Button {
                        onGiveLesson?(lesson)
                    } label: {
                        Label("Give Lesson", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        seedDrafts()
                        isEditing = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onClose()
                    } label: {
                        Label("Done", systemImage: "checkmark.circle.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            .labelStyle(.titleAndIcon)
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
                // Trigger the Give Lesson flow immediately and then close the detail card if needed
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
                _ = saveCoordinator.save(modelContext, reason: "Delete lesson")
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
                            _ = saveCoordinator.save(modelContext, reason: "Import lesson Pages file")
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
    }

    func resolvePagesURL() -> URL? {
        guard let bookmark = lesson.pagesFileBookmark else { return nil }
        var stale = false
        do {
#if os(macOS)
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil, bookmarkDataIsStale: &stale
            )
#else
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil, bookmarkDataIsStale: &stale
            )
#endif
            if stale {
#if os(macOS)
                let newBookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
#else
                let newBookmark = try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
#endif
                lesson.pagesFileBookmark = newBookmark
            }
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }

    func resolveLessonFileURL() -> URL? {
        // Prefer relative path inside managed container
        if let rel = lesson.pagesFileRelativePath, !rel.isEmpty {
            do {
                return try LessonFileStorage.resolve(relativePath: rel)
            } catch {
                Self.logger.warning("Failed to resolve relative path: \(error)")
            }
        }
        // Fallback to legacy bookmark
        return resolvePagesURL()
    }

    func migrateLegacyLinkedFileIfNeeded() {
        // Only migrate if we don't already have a relative path but do have a bookmark
        guard lesson.pagesFileRelativePath == nil, lesson.pagesFileBookmark != nil else { return }
        // Resolve the legacy bookmark URL directly (do not prefer relative path here)
        guard let legacyURL = resolvePagesURL(), !LessonFileStorage.isManagedURL(legacyURL) else { return }
        Task(priority: .utility) {
            do {
                let destURL = try LessonFileStorage.importFile(
                    from: legacyURL,
                    forLessonWithID: lesson.id,
                    lessonName: lesson.name
                )
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

    var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
    
    #if os(macOS)
    func presentMacOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = pagesAllowedTypes
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task(priority: .userInitiated) {
                    do {
                        let destURL = try LessonFileStorage.importFile(
                            from: url,
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
            }
        }
    }
    #endif

    func openInPages(_ url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        #if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #elseif os(macOS)
        if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(
                [url], withApplicationAt: pagesAppURL,
                configuration: config, completionHandler: nil
            )
        } else {
            NSWorkspace.shared.open(url)
        }
        #endif
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
