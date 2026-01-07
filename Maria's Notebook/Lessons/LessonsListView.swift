// Maria's Notebook/Lessons/LessonsListView.swift

import SwiftUI
import SwiftData

/// Curriculum-only list view for lessons inside a selected subject+group.
/// Shows Section headers by subheading (if present) and supports lesson reordering (List-only).
struct LessonsListView: View {
    let subject: String
    let group: String
    let lessons: [Lesson]

    let canReorderLessons: Bool
    let onMoveLesson: (_ source: IndexSet, _ destination: Int, _ orderedSubset: [Lesson]) -> Void

    private var lessonsInGroup: [Lesson] {
        lessons
            .filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
            .filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }
    }

    private var orderedLessons: [Lesson] {
        lessonsInGroup.sorted { lhs, rhs in
            if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var subheadingOrder: [String] {
        let existing = Array(Set(orderedLessons.map { $0.subheading.trimmed() }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadSubheadingOrder(for: subject, group: group, existing: existing)
    }

    var body: some View {
        List {
            // If there are subheadings, present as structural sections.
            if !subheadingOrder.isEmpty {
                ForEach(subheadingOrder, id: \.self) { sh in
                    let items = orderedLessons.filter { $0.subheading.trimmed() == sh }
                    if !items.isEmpty {
                        Section(header: Text(sh)) {
                            ForEach(items, id: \.id) { lesson in
                                LessonRow(lesson: lesson)
                            }
                            .onMove(perform: canReorderLessons ? { source, destination in
                                // IMPORTANT: onMove needs a single ordered subset.
                                // Here we reorder within the subheading section only.
                                onMoveLesson(source, destination, items)
                            } : nil)
                        }
                    }
                }

                // Lessons with no subheading go at the end (optional section)
                let noSub = orderedLessons.filter { $0.subheading.trimmed().isEmpty }
                if !noSub.isEmpty {
                    Section(header: Text("Other")) {
                        ForEach(noSub, id: \.id) { lesson in
                            LessonRow(lesson: lesson)
                        }
                        .onMove(perform: canReorderLessons ? { source, destination in
                            onMoveLesson(source, destination, noSub)
                        } : nil)
                    }
                }
            } else {
                // No subheadings: single list
                ForEach(orderedLessons, id: \.id) { lesson in
                    LessonRow(lesson: lesson)
                }
                .onMove(perform: canReorderLessons ? { source, destination in
                    onMoveLesson(source, destination, orderedLessons)
                } : nil)
            }
        }
        .listStyle(.inset)
        .contentMargins(.leading, 0, for: .scrollContent)
        .contentMargins(.trailing, 0, for: .scrollContent)
        .navigationTitle(group)
    }
}

private struct LessonRow: View {
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.secondary.opacity(0.35))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(1)

                Text("\(lesson.subject) · \(lesson.group)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Structural affordance only (no student tracking)
            Image(systemName: "tag.fill")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.45))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
