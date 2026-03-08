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

    // MODERN: Computed properties - no manual cache management needed
    
    private var lessonsInGroup: [Lesson] {
        lessons
            .filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
            .filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }
    }

    private var orderedLessons: [Lesson] {
        lessonsInGroup.sorted { lhs, rhs in
            if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame { return nameCompare == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
    
    /// Automatically recomputes when orderedLessons changes
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
                                LessonRow(lesson: lesson, secondaryTextStyle: .subjectAndGroup, showTagIcon: true)
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
                            LessonRow(lesson: lesson, secondaryTextStyle: .subjectAndGroup, showTagIcon: true)
                        }
                        .onMove(perform: canReorderLessons ? { source, destination in
                            onMoveLesson(source, destination, noSub)
                        } : nil)
                    }
                }
            } else {
                // No subheadings: single list
                ForEach(orderedLessons, id: \.id) { lesson in
                    LessonRow(lesson: lesson, secondaryTextStyle: .subjectAndGroup, showTagIcon: true)
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
