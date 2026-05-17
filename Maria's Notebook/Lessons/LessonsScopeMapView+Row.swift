// Maria's Notebook/Lessons/LessonsScopeMapView+Row.swift
//
// Thread row used by LessonsScopeMapView: leading colored bar, sequence label,
// and pills tinted in the area's hue. Default state shows pills as a single
// horizontal-scrolling row; hover (macOS) or edit mode expands inline so pills
// wrap across multiple lines.

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

    @State private var isHovered: Bool = false

    private let labelColumnWidth: CGFloat = 180
    private let collapsedHeight: CGFloat = 38
    private let barWidth: CGFloat = 3

    /// Wrap pills onto multiple lines when hovered or while edit mode is active.
    private var isExpanded: Bool { isHovered || isEditing }

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
                    Text("\(lessons.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 22, alignment: .trailing)
                        .padding(.top, isExpanded ? 7 : 0)
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
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var pillsContainer: some View {
        if isExpanded {
            FlowLayout(spacing: 5) {
                ForEach(lessons, id: \.objectID) { lesson in
                    MiniLessonPill(name: lesson.name, color: color)
                }
            }
            .padding(.vertical, 5)
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
