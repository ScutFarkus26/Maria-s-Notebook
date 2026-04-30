// Maria's Notebook/Lessons/LessonsScopeThreadFocusView.swift
//
// Drill-in view for one (subject, group) thread on the scope-and-sequence map.
// Renders full-size labeled pills in sequence order; tapping one opens
// LessonDetailView via the parent's selection binding.

import SwiftUI
import CoreData

struct LessonsScopeThreadFocusView: View {
    let threadKey: ThreadKey
    let lessons: [CDLesson]
    let onBack: () -> Void
    let onSelectLesson: (CDLesson) -> Void
    let onShowInBrowse: (CDLesson) -> Void

    private var color: Color {
        AppColors.color(forSubject: threadKey.subject)
    }

    private var sortedLessons: [CDLesson] {
        lessons.sorted(by: ThreadRowData.lessonSortOrder)
    }

    var body: some View {
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

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock

                FlowLayout(spacing: 8) {
                    ForEach(sortedLessons, id: \.objectID) { lesson in
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
                            Button {
                                onSelectLesson(lesson)
                            } label: {
                                Label("Open Card", systemImage: "doc.text")
                            }
                            Button {
                                onShowInBrowse(lesson)
                            } label: {
                                Label("View in Browse", systemImage: "square.grid.2x2")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(threadKey.subject.uppercased())
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

