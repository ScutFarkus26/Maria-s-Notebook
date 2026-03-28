import OSLog
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Header, Title, Bottom Bar & Helpers

extension LessonDetailCard {

    @ViewBuilder
    var headerBar: some View {
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
    }

    @ViewBuilder
    var titleAndBadges: some View {
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
                if lesson.isStory {
                    Text("Story")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                        .foregroundStyle(.purple)
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
    }

    // swiftlint:disable:next function_body_length
    @ViewBuilder
    var bottomBar: some View {
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
                    updated.lessonFormat = draftLessonFormat
                    updated.parentStoryUUID = draftLessonFormat == .story ? draftParentStoryID : nil
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

    var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    // MARK: - File Handling

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
        if let rel = lesson.pagesFileRelativePath, !rel.isEmpty {
            do {
                return try LessonFileStorage.resolve(relativePath: rel)
            } catch {
                Self.logger.warning("Failed to resolve relative path: \(error)")
            }
        }
        return resolvePagesURL()
    }

    func migrateLegacyLinkedFileIfNeeded() {
        guard lesson.pagesFileRelativePath == nil, lesson.pagesFileBookmark != nil else { return }
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
                    saveCoordinator.save(modelContext, reason: "Migrate lesson file to managed storage")
                }
            } catch {
                await MainActor.run { importError = error.localizedDescription }
            }
        }
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
                            saveCoordinator.save(modelContext, reason: "Import lesson Pages file")
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
