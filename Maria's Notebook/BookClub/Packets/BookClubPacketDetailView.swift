import SwiftUI
import CoreData
import OSLog

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct BookClubPacketDetailView: View {
    @ObservedObject var packet: CDBookClubPacket
    @Environment(\.managedObjectContext) private var viewContext
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var newThemeText: String = ""
    @State private var newReadingLabel: String = ""
    @State private var showingDeleteConfirm = false
    @State private var showingSessionEditor = false

    nonisolated private static let logger = Logger.bookClub

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroImageSection
                    titleSection
                    authorSection
                    gradeSection
                    themesSection
                    readingItemsSection
                    teachingNotesSection
                    actionButtons
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showingSessionEditor) {
            BookClubSessionEditorSheet(prefilledPacket: packet)
                .frame(minWidth: 560, minHeight: 600)
        }
        .confirmationDialog(
            "Delete this packet?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deletePacket() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The PDF and all packet details will be removed. " +
                "Sessions referencing this packet will remain but lose their link."
            )
        }
    }

    private var header: some View {
        HStack {
            Text(packet.displayTitle)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var heroImageSection: some View {
        // Decoded through the shared cache (same key as `BookClubPacketCardView`)
        // instead of in `body`, which re-ran the decode on every Core Data merge.
        if let image = CachedThumbnail.image(
            from: packet.thumbnailData,
            cacheKey: packet.objectID.uriRepresentation().absoluteString
        ) {
            #if os(macOS)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            #else
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            #endif
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                Image(systemName: "book.pages")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Title")
            TextField("Untitled Book Club", text: Binding(
                get: { packet.title },
                set: { packet.title = $0; touch() }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    private var authorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Author")
            TextField("e.g. Astrid Lindgren", text: Binding(
                get: { packet.author },
                set: { packet.author = $0; touch() }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Grade band")
            HStack(spacing: 8) {
                gradePicker(label: "From", selection: Binding(
                    get: { packet.gradeMin },
                    set: { packet.gradeMin = $0; touch() }
                ))
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                gradePicker(label: "To", selection: Binding(
                    get: { packet.gradeMax },
                    set: { packet.gradeMax = $0; touch() }
                ))
            }
        }
    }

    private func gradePicker(label: String, selection: Binding<StoryGrade?>) -> some View {
        Picker(label, selection: selection) {
            Text("Any").tag(StoryGrade?.none)
            ForEach(StoryGrade.allCases) { grade in
                Text(grade.longLabel).tag(StoryGrade?.some(grade))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Themes")
            if !packet.themesArray.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(packet.themesArray, id: \.self) { theme in
                        StoryThemeChip(theme, variant: .removable(action: { removeTheme(theme) }))
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Add a theme", text: $newThemeText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTheme() }
                Button("Add", action: addTheme)
                    .disabled(newThemeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var readingItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Reading items")
            Text(
                "These chapter splits are copied into each new club session. " +
                "Edit dates and assignments per session later."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(packet.readingItems) { item in
                    readingItemRow(item)
                }
            }
            HStack(spacing: 8) {
                TextField("e.g. Chapters 1\u{2013}3", text: $newReadingLabel)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addReadingItem() }
                Button("Add", action: addReadingItem)
                    .disabled(newReadingLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func readingItemRow(_ item: BookClubReadingItem) -> some View {
        HStack(spacing: 10) {
            Text("\(item.ordinal).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            TextField("Label", text: Binding(
                get: { item.label },
                set: { renameReadingItem(item, to: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            Button { removeReadingItem(item) } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var teachingNotesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Teaching notes")
            TextEditor(text: Binding(
                get: { packet.teachingNotes },
                set: { packet.teachingNotes = $0; touch() }
            ))
            .frame(minHeight: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                showingSessionEditor = true
            } label: {
                Label("Start New Club", systemImage: "person.3.sequence")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(packet.readingItems.isEmpty)

            if packet.readingItems.isEmpty {
                Text("Add reading items to start a club.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button { openPDF() } label: {
                    Label("Open PDF", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(resolvedURL() == nil)

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Actions

    private func touch() {
        packet.modifiedAt = Date()
        viewContext.safeSave()
    }

    private func addTheme() {
        let trimmed = newThemeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var themes = packet.themesArray
        if !themes.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            themes.append(trimmed)
            packet.themesArray = themes
            touch()
        }
        newThemeText = ""
    }

    private func removeTheme(_ theme: String) {
        packet.themesArray = packet.themesArray.filter { $0 != theme }
        touch()
    }

    private func addReadingItem() {
        let trimmed = newReadingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = packet.readingItems
        let nextOrdinal = (items.map(\.ordinal).max() ?? 0) + 1
        items.append(BookClubReadingItem(ordinal: nextOrdinal, label: trimmed))
        packet.readingItems = items
        touch()
        newReadingLabel = ""
    }

    private func renameReadingItem(_ item: BookClubReadingItem, to newLabel: String) {
        var items = packet.readingItems
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].label = newLabel
        packet.readingItems = items
        touch()
    }

    private func removeReadingItem(_ item: BookClubReadingItem) {
        var items = packet.readingItems.filter { $0.id != item.id }
        for index in items.indices {
            items[index].ordinal = index + 1
        }
        packet.readingItems = items
        touch()
    }

    private func resolvedURL() -> URL? {
        BookClubFileStorage.resolveURL(
            bookmark: packet.packetPDFBookmark,
            relativePath: packet.packetPDFRelativePath
        )
    }

    private func openPDF() {
        guard let url = resolvedURL() else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    private func deletePacket() {
        if let url = resolvedURL() {
            try? BookClubFileStorage.deleteIfManaged(url)
        }
        viewContext.delete(packet)
        viewContext.safeSave()
        onDelete()
    }
}
