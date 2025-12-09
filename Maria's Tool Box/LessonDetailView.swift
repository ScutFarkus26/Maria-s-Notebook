import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct LessonDetailView: View {
    var lesson: Lesson
    var onSave: (Lesson) -> Void
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Lesson Info")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Divider()
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 28) {
                    headerContent
                        .padding(.top, 36)

                    if isEditing {
                        editForm
                    } else {
                        infoSection
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .alert("Delete Lesson?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(lesson)
                if let onDone { onDone() } else { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear {
            seedDrafts()
            resolvedPagesURL = resolvePagesURL()
        }
        .fileImporter(
            isPresented: $showingPagesImporter,
            allowedContentTypes: [UTType(filenameExtension: "pages")!]
        ) { result in
            switch result {
            case .success(let url):
                savePagesBookmark(from: url)
                resolvedPagesURL = resolvePagesURL()
            case .failure(let error):
                importError = error.localizedDescription
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
        VStack(spacing: 12) {
            Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                .font(.system(size: AppTheme.FontSize.titleXLarge, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoRow(icon: "text.book.closed", title: "Name", value: lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
            infoRow(icon: "graduationcap", title: "Subject", value: lesson.subject.isEmpty ? "—" : lesson.subject)
            infoRow(icon: "square.grid.2x2", title: "Group", value: lesson.group.isEmpty ? "—" : lesson.group)
            infoRow(icon: "text.bubble", title: "Subheading", value: lesson.subheading.isEmpty ? "—" : lesson.subheading)

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
                    Text(lesson.writeUp)
                        .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)

            if let url = resolvedPagesURL {
                HStack { Spacer() }
                OpenInPagesButton(title: "Open in Pages") { openInPages(url) }
                    .padding(.vertical, 8)
                HStack { Spacer() }
            }
        }
        .padding(.horizontal, 8)
    }

    private var editForm: some View {
        VStack(spacing: 14) {
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
                        Button("Choose…") { showingPagesImporter = true }
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
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
            }
        }
        .padding(.horizontal, 8)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
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

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                if isEditing {
                    Button("Cancel") { isEditing = false }
                    Button("Save") {
                        let updated = lesson
                        updated.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.subject = draftSubject.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.group = draftGroup.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.subheading = draftSubheading.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.writeUp = draftWriteUp
                        onSave(updated)
                        isEditing = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
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
        guard let bookmarkData = lesson.pagesFileBookmark else {
            return nil
        }

        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI, .withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)

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

    private func savePagesBookmark(from url: URL) {
#if os(iOS)
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            lesson.pagesFileBookmark = bookmark
        } catch {
            // ignore error
        }
#elseif os(macOS)
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            lesson.pagesFileBookmark = bookmark
        } catch {
            // ignore error
        }
#endif
    }

    private func clearPagesLink() {
        lesson.pagesFileBookmark = nil
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
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.15))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LessonDetailView(
        lesson: Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Intro to base-10", writeUp: "This is a sample write up."),
        onSave: { _ in }
    )
}

