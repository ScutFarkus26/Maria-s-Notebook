// Maria's Notebook/Lessons/LessonsScopeThreadFocusView.swift
//
// Drill-in view for one (area, sequence) thread on the scope-and-sequence map.
// Renders full-size labeled pills in sequence order; tapping one opens
// LessonDetailView via the parent's selection binding.
// In edit mode, pills can be drag-reordered and expose context menus for moving.

import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Lesson drag-drop payload

struct LessonTransfer: Codable, Transferable {
    let lessonID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Section drag-drop payload

struct ThreadSectionTransfer: Codable, Transferable {
    let area: String
    let sequence: String
    let section: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - LessonsScopeThreadFocusView

struct LessonsScopeThreadFocusView: View {
    let threadKey: ThreadKey
    let lessons: [CDLesson]
    /// All sequences in this area — used for "Move to Sequence" submenu.
    var sequences: [String] = []
    var isEditing: Bool = false
    let onBack: () -> Void
    let onSelectLesson: (CDLesson) -> Void
    var onMoveLessonEarlier: ((CDLesson) -> Void)?
    var onMoveLessonLater: ((CDLesson) -> Void)?
    var onMoveLessonToSequence: ((CDLesson, String) -> Void)?
    /// Right-click → insert a new lesson directly after the source lesson, with area,
    /// sequence, and section pre-filled from the source.
    var onCreateLessonAfter: ((CDLesson) -> Void)?
    /// Drag-reorder callback. Source IndexSet and destination index match SwiftUI's
    /// `.onMove` convention so it can call `moveLessonsInArea` directly.
    var onReorderLessons: ((IndexSet, Int) -> Void)?

    @State private var dropTargetLessonID: UUID?
    @State private var dropTargetSection: String?
    @State private var sectionOrderVersion: Int = 0

    private var color: Color {
        AppColors.color(forArea: threadKey.area)
    }

    private var sortedLessons: [CDLesson] {
        lessons.sorted(by: ThreadRowData.lessonSortOrder)
    }

    var body: some View {
        let _ = sectionOrderVersion
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Label("Map", systemImage: "chevron.backward")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sectionedGroups: [(String, [CDLesson])] {
        let sorted = sortedLessons
        let existing = Array(Set(sorted.map { $0.section.trimmed() }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let order = FilterOrderStore.loadSectionOrder(for: threadKey.area, sequence: threadKey.sequence, existing: existing)
        var result: [(String, [CDLesson])] = order.compactMap { name in
            let group = sorted.filter { $0.section.trimmed().caseInsensitiveCompare(name) == .orderedSame }
            return group.isEmpty ? nil : (name, group)
        }
        let unsectioned = sorted.filter { $0.section.trimmed().isEmpty }
        if !unsectioned.isEmpty { result.append(("", unsectioned)) }
        return result
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                pillGroups
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var pillGroups: some View {
        let groups = sectionedGroups
        let hasSections = groups.contains(where: { !$0.0.isEmpty })

        if hasSections {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(groups.enumerated()), id: \.offset) { entry in
                    sectionGroupView(name: entry.element.0, lessons: entry.element.1)
                }
            }
        } else {
            FlowLayout(spacing: 8) {
                ForEach(sortedLessons, id: \.objectID) { lesson in
                    pillView(for: lesson)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionGroupView(name sectionName: String, lessons sectionLessons: [CDLesson]) -> some View {
        let isNamed = !sectionName.isEmpty
        let isDropTarget = isNamed && (dropTargetSection?.caseInsensitiveCompare(sectionName) == .orderedSame)

        VStack(alignment: .leading, spacing: 6) {
            if isNamed {
                Text(sectionName.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(color.opacity(0.7))
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .draggable(ThreadSectionTransfer(
                        area: threadKey.area,
                        sequence: threadKey.sequence,
                        section: sectionName
                    ))
                    .help("Drag to reorder section")
            }
            FlowLayout(spacing: 8) {
                ForEach(sectionLessons, id: \.objectID) { lesson in
                    pillView(for: lesson)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(isDropTarget ? 0.6 : 0), lineWidth: 1.5)
                .padding(-6)
        )
        .when(isNamed) { view in
            view.dropDestination(for: ThreadSectionTransfer.self) { items, _ in
                handleSectionDrop(items: items, onto: sectionName)
            } isTargeted: { isTargeted in
                if isTargeted {
                    dropTargetSection = sectionName
                } else if dropTargetSection?.caseInsensitiveCompare(sectionName) == .orderedSame {
                    dropTargetSection = nil
                }
            }
        }
    }

    private func handleSectionDrop(items: [ThreadSectionTransfer], onto targetSection: String) -> Bool {
        defer { dropTargetSection = nil }
        guard let item = items.first,
              item.area.caseInsensitiveCompare(threadKey.area) == .orderedSame,
              item.sequence.caseInsensitiveCompare(threadKey.sequence) == .orderedSame,
              item.section.caseInsensitiveCompare(targetSection) != .orderedSame
        else { return false }

        let names = sectionedGroups.map { $0.0 }.filter { !$0.isEmpty }
        guard let srcIdx = names.firstIndex(where: {
            $0.caseInsensitiveCompare(item.section) == .orderedSame
        }), let dstIdx = names.firstIndex(where: {
            $0.caseInsensitiveCompare(targetSection) == .orderedSame
        }) else { return false }

        var newOrder = names
        let moved = newOrder.remove(at: srcIdx)
        let insertIdx = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
        newOrder.insert(moved, at: insertIdx)

        FilterOrderStore.saveSectionOrder(newOrder, for: threadKey.area, sequence: threadKey.sequence)
        FilterOrderStore.resetCache()
        sectionOrderVersion &+= 1
        return true
    }

    @ViewBuilder
    private func pillView(for lesson: CDLesson) -> some View {
        let isDropTarget = (dropTargetLessonID == lesson.id)

        AppPillButton(
            isSelected: false,
            selectionStyle: .accentOutline,
            action: { onSelectLesson(lesson) }
        ) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(lesson.name)
            }
        }
        .contextMenu {
            pillContextMenu(for: lesson)
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.accentColor.opacity(isDropTarget ? 0.8 : 0), lineWidth: 1.5)
        )
        .when(lesson.id != nil) { view in
            view
                .draggable(LessonTransfer(lessonID: lesson.id!))
                .dropDestination(for: LessonTransfer.self) { items, _ in
                    handleDrop(items: items, onto: lesson)
                } isTargeted: { isTargeted in
                    if isTargeted {
                        dropTargetLessonID = lesson.id
                    } else if dropTargetLessonID == lesson.id {
                        dropTargetLessonID = nil
                    }
                }
        }
    }

    private func handleDrop(items: [LessonTransfer], onto target: CDLesson) -> Bool {
        guard let item = items.first,
              let targetID = target.id,
              item.lessonID != targetID
        else { return false }

        let ids = sortedLessons.compactMap(\.id)
        guard let srcIdx = ids.firstIndex(of: item.lessonID),
              let dstIdx = ids.firstIndex(of: targetID)
        else { return false }

        // SwiftUI's onMove convention: when moving down, destination is one past the target index.
        let adjustedDst = dstIdx > srcIdx ? dstIdx + 1 : dstIdx
        onReorderLessons?(IndexSet(integer: srcIdx), adjustedDst)
        return true
    }

    @ViewBuilder
    private func pillContextMenu(for lesson: CDLesson) -> some View {
        Button {
            onSelectLesson(lesson)
        } label: {
            Label("Open Card", systemImage: "doc.text")
        }

        if let onCreateLessonAfter {
            Divider()
            Button {
                onCreateLessonAfter(lesson)
            } label: {
                Label("New Lesson After", systemImage: "plus")
            }
        }

        if isEditing {
            Divider()

            let sorted = sortedLessons
            let isFirst = sorted.first?.id == lesson.id
            let isLast = sorted.last?.id == lesson.id

            if !isFirst, let onMoveLessonEarlier {
                Button {
                    onMoveLessonEarlier(lesson)
                } label: {
                    Label("Move Earlier", systemImage: "arrow.backward")
                }
            }

            if !isLast, let onMoveLessonLater {
                Button {
                    onMoveLessonLater(lesson)
                } label: {
                    Label("Move Later", systemImage: "arrow.forward")
                }
            }

            let otherSequences = sequences.filter {
                $0.trimmed().caseInsensitiveCompare(threadKey.sequence.trimmed()) != .orderedSame
            }
            if !otherSequences.isEmpty, let onMoveLessonToSequence {
                Divider()
                Menu("Move to Sequence\u{2026}") {
                    ForEach(otherSequences, id: \.self) { target in
                        Button(target) {
                            onMoveLessonToSequence(lesson, target)
                        }
                    }
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(threadKey.area.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(color)

            Text(threadKey.displayName)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text("\(sortedLessons.count) lesson\(sortedLessons.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
