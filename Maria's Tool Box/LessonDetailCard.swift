import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

public enum LessonDetailInitialMode {
    case normal
    case giveLesson
}

struct LessonDetailCard: View {
    var lesson: Lesson
    var onSave: (Lesson) -> Void
    var onClose: () -> Void
    var onGiveLesson: ((Lesson) -> Void)? = nil
    var initialMode: LessonDetailInitialMode = .normal

    @Environment(\.modelContext) private var modelContext

    @State private var isEditing = false
    @State private var draftName: String = ""
    @State private var draftSubject: String = ""
    @State private var draftGroup: String = ""
    @State private var draftSubheading: String = ""
    @State private var draftWriteUp: String = ""
    @State private var showDeleteAlert = false

    @State private var showingPagesImporter = false
    @State private var resolvedPagesURL: URL? = nil
    @State private var importError: String? = nil

#if canImport(UniformTypeIdentifiers)
    private var pagesAllowedTypes: [UTType] {
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
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
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
                    .font(.system(size: AppTheme.FontSize.titleLarge, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    if !lesson.subject.isEmpty {
                        Text(lesson.subject)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                    if !lesson.group.isEmpty {
                        Text(lesson.group)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
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
                        updated.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.subject = draftSubject.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.group = draftGroup.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.subheading = draftSubheading.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.writeUp = draftWriteUp
                        onSave(updated)
                        isEditing = false
                    } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            resolvedPagesURL = resolvePagesURL()
        }
        .alert("Delete Lesson?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(lesson)
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
                let url = try result.get()
                let needsAccess = url.startAccessingSecurityScopedResource()
                defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                savePagesBookmark(from: url)
                resolvedPagesURL = url
            } catch {
                importError = error.localizedDescription
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
        .accessibilityElement(children: .contain)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = resolvedPagesURL {
                HStack { Spacer() }
                OpenInPagesButton(title: "Open in Pages") { openInPages(url) }
                    .padding(.vertical, 8)
                HStack { Spacer() }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.plaintext")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Notes")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if lesson.writeUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(lesson.writeUp)
                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180, maxHeight: 360)
                }
            }
            .padding(.top, 6)
        }
    }

    private var editForm: some View {
        VStack(spacing: 12) {
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Linked Pages File")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if resolvedPagesURL != nil {
                            Button("Remove") {
                                clearPagesLink()
                                resolvedPagesURL = nil
                            }
                        }
                        Button("Choose…") {
                            #if os(macOS)
                            presentMacOpenPanel()
                            #else
                            showingPagesImporter = true
                            #endif
                        }
                    }
                    if let url = resolvedPagesURL {
                        OpenInPagesButton(title: "Open in Pages") { openInPages(url) }
                            .padding(.top, 4)
                    } else {
                        Text("No file selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftWriteUp)
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
            }
        }
    }

    private func row(title: String, value: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
        }
    }

    private func seedDrafts() {
        draftName = lesson.name
        draftSubject = lesson.subject
        draftGroup = lesson.group
        draftSubheading = lesson.subheading
        draftWriteUp = lesson.writeUp
    }

    private func resolvePagesURL() -> URL? {
        guard let bookmark = lesson.pagesFileBookmark else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                let newBookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                lesson.pagesFileBookmark = newBookmark
            }
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }

    private func savePagesBookmark(from url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            lesson.pagesFileBookmark = bookmark
            try? modelContext.save()
        } catch {
            // ignore errors here
        }
    }

    private func clearPagesLink() {
        lesson.pagesFileBookmark = nil
        try? modelContext.save()
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
    
    #if os(macOS)
    private func presentMacOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = pagesAllowedTypes
        } else {
            panel.allowedFileTypes = ["pages"]
        }
        panel.begin { response in
            if response == .OK, let url = panel.url {
                savePagesBookmark(from: url)
                resolvedPagesURL = url
            }
        }
    }
    #endif

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

#Preview {
    LessonDetailCard(
        lesson: Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Intro to base-10", writeUp: "A foundational presentation of the decimal system."),
        onSave: { _ in },
        onClose: {},
        onGiveLesson: nil,
        initialMode: .normal
    )
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.15))
}
