// Maria's Notebook/Lessons/LessonsScopeMapView+Row.swift
//
// Thread row used by LessonsScopeMapView: leading colored bar, sequence label,
// and pills tinted in the area's hue. Default state shows pills as a single
// horizontal-scrolling row; clicking the count chevron pins the row open
// (wrapped multi-line). Edit mode auto-expands every row.

import SwiftUI
import CoreData

struct ThreadRow: View {
    let threadKey: ThreadKey
    let lessons: [CDLesson]
    let color: Color
    var isEditing: Bool = false
    var hasSections: Bool = false
    let onTap: () -> Void
    var onConfigureTrack: (() -> Void)?
    var onReorderSections: (() -> Void)?

    @State private var isPinned: Bool = false

    private let labelColumnWidth: CGFloat = 180
    private let collapsedHeight: CGFloat = 38
    private let barWidth: CGFloat = 3

    /// Wrap pills onto multiple lines when the user has pinned this row open
    /// (via the count chevron) or while edit mode is active.
    private var isExpanded: Bool { isPinned || isEditing }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: isExpanded ? .top : .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.85))
                    .frame(width: barWidth, height: isExpanded ? 14 : (collapsedHeight - 12))
                    .padding(.top, isExpanded ? 9 : 0)

                Text(threadKey.displayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: labelColumnWidth, alignment: .leading)
                    .padding(.top, isExpanded ? 5 : 0)

                pillsContainer

                Spacer(minLength: 8)

                if isEditing {
                    editControls
                        .padding(.top, isExpanded ? 5 : 0)
                } else {
                    pinToggleButton
                        .padding(.top, isExpanded ? 5 : 0)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: collapsedHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(0.18), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Count badge that toggles persistent expansion. The chevron + count gives
    /// the affordance that "more is here"; clicking pins/unpins the row.
    private var pinToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isPinned.toggle()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isPinned ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text("\(lessons.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(minWidth: 30, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Collapse" : "Show all lessons")
    }

    private var sectionedGroups: [(String, [CDLesson])] {
        let existing = Array(Set(lessons.map { $0.section.trimmed() }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let order = FilterOrderStore.loadSectionOrder(for: threadKey.area, sequence: threadKey.sequence, existing: existing)
        var result: [(String, [CDLesson])] = order.compactMap { name in
            let group = lessons.filter { $0.section.trimmed().caseInsensitiveCompare(name) == .orderedSame }
            return group.isEmpty ? nil : (name, group)
        }
        let unsectioned = lessons.filter { $0.section.trimmed().isEmpty }
        if !unsectioned.isEmpty { result.append(("", unsectioned)) }
        return result
    }

    @ViewBuilder
    private var pillsContainer: some View {
        if isExpanded {
            let groups = sectionedGroups
            let hasSections = groups.contains(where: { !$0.0.isEmpty })

            if hasSections {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { entry in
                        let sectionName = entry.element.0
                        let sectionLessons = entry.element.1
                        VStack(alignment: .leading, spacing: 4) {
                            if !sectionName.isEmpty {
                                Text(sectionName.uppercased())
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .tracking(0.4)
                                    .foregroundStyle(.secondary)
                            }
                            FlowLayout(spacing: 5) {
                                ForEach(sectionLessons, id: \.objectID) { lesson in
                                    MiniLessonPill(name: lesson.name, color: color)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 5)
            } else {
                FlowLayout(spacing: 5) {
                    ForEach(lessons, id: \.objectID) { lesson in
                        MiniLessonPill(name: lesson.name, color: color)
                    }
                }
                .padding(.vertical, 5)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(lessons, id: \.objectID) { lesson in
                        MiniLessonPill(name: lesson.name, color: color)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder
    private var editControls: some View {
        HStack(spacing: 6) {
            if hasSections, let onReorderSections {
                Button(action: onReorderSections) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reorder sections")
            }
            if let onConfigureTrack {
                Button(action: onConfigureTrack) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Configure track settings")
            }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 22)
        }
    }
}

/// Compact named pill representing a single lesson in the scope-and-sequence map.
/// Shows the lesson name directly on the pill, tinted in the area color.
struct MiniLessonPill: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.55), lineWidth: 0.75)
            )
            .help(name)
            .accessibilityLabel(name)
    }
}
