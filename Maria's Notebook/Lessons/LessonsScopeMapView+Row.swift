// Maria's Notebook/Lessons/LessonsScopeMapView+Row.swift
//
// Thread row used by LessonsScopeMapView: leading colored bar, sequence label,
// and a horizontal strip of named lesson pills tinted in the area's hue.

import SwiftUI
import CoreData

struct ThreadRow: View {
    let threadKey: ThreadKey
    let lessons: [CDLesson]
    let color: Color
    let onTap: () -> Void

    private let labelColumnWidth: CGFloat = 180
    private let rowHeight: CGFloat = 38
    private let barWidth: CGFloat = 3

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.85))
                    .frame(width: barWidth, height: rowHeight - 12)

                Text(threadKey.displayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: labelColumnWidth, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(lessons, id: \.objectID) { lesson in
                            MiniLessonPill(name: lesson.name, color: color)
                        }
                    }
                    .padding(.vertical, 3)
                }

                Spacer(minLength: 8)

                Text("\(lessons.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 22, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: rowHeight)
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
