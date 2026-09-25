// ObservationsView+List.swift
// List rendering, rows, and data loading for ObservationsView

import SwiftUI
import CoreData

extension ObservationsView {
    // MARK: - Observations List

    var observationsList: some View {
        // Filtered once per pass; it was computed twice (emptiness, then rows).
        let filteredItems = filteredItems
        return List {
            if filteredItems.isEmpty, !isLoading {
                ContentUnavailableView("No observations", systemImage: "note.text")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(filteredItems, id: \.id) { item in
                    observationRow(for: item)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Observation Row

    @ViewBuilder
    func observationRow(for item: UnifiedObservationItem) -> some View {
        row(for: item)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                if isSelecting {
                    Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedItemIDs.contains(item.id) ? Color.accentColor : .secondary)
                }
            }
            .onTapGesture {
                if isSelecting {
                    if selectedItemIDs.contains(item.id) {
                        selectedItemIDs.remove(item.id)
                    } else {
                        selectedItemIDs.insert(item.id)
                    }
                } else {
                    editItem(item)
                }
            }
    }

    // MARK: - Row Content

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func row(for item: UnifiedObservationItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(.tint)

                if !item.tags.isEmpty {
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                }

                // Show context badge if note is attached to a specific entity
                if let contextText = item.contextText {
                    Text(contextText)
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .capsuleFill(Color.secondary.opacity(UIConstants.OpacityConstants.light))
                }

                Spacer()
                Text(item.date.formatted(.relative(presentation: .named)))
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
            if let firstLine = firstLine(of: item.body) {
                Text(firstLine)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            if !item.studentIDs.isEmpty {
                // Wraps rather than scrolls: no scroll view per row.
                FlowLayout(spacing: 6) {
                    ForEach(item.studentIDs.prefix(3), id: \.self) { sid in
                        if let s = studentsByID[sid] {
                            studentChip(s.shortName)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
    #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button {
                editItem(item)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    #endif
        .contextMenu {
            Button {
                editItem(item)
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }

    // MARK: - Edit

    func editItem(_ item: UnifiedObservationItem) {
        switch item.source {
        case .note(let note):
            noteBeingEdited = note
        }
    }

    // MARK: - Row Helpers

    func studentChip(_ name: String) -> some View {
        Text(name)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .capsuleFill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
    }

    func firstLine(of text: String) -> String? {
        let trimmed = text.trimmed()
        guard !trimmed.isEmpty else { return nil }
        if let newline = trimmed.firstIndex(of: "\n") {
            return String(trimmed[..<newline])
        }
        return trimmed
    }

    // MARK: - Data Loading

    func loadFirstPageIfNeeded() {
        if loadedItems.isEmpty && !isLoading {
            Task { await loadAllNotes() }
        }
    }

    func reloadAllNotes() {
        loadedItems = []
        usedTags = []
        lastCursorDate = nil
        hasMore = true
        Task { await loadAllNotes() }
    }

    func loadAllNotes() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        loadedItems = ObservationsDataLoader.loadAllNotes(context: viewContext)
        usedTags = ObservationsFilterService.usedTags(in: loadedItems)
        hasMore = false
        loadStudentsIfNeeded(for: filteredItems)
    }

    func loadStudentsIfNeeded(for items: [UnifiedObservationItem]) {
        studentsByID = ObservationsDataLoader.loadStudents(
            for: items,
            existingCache: studentsByID,
            context: viewContext
        )
    }

}
