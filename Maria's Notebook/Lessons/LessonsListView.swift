// Maria's Notebook/Lessons/LessonsListView.swift

import SwiftUI
import CoreData

/// Curriculum-only list view for lessons inside a selected area+sequence.
/// Shows Section headers by section (if present) and supports lesson reordering (List-only).
struct LessonsListView: View {
    let area: String
    let sequence: String
    let lessons: [CDLesson]

    let canReorderLessons: Bool
    let onMoveLesson: (_ source: IndexSet, _ destination: Int, _ orderedSubset: [CDLesson]) -> Void

    // MODERN: Computed properties - no manual cache management needed
    
    private var lessonsInSequence: [CDLesson] {
        lessons.filter { (lesson: CDLesson) -> Bool in
            lesson.area.caseInsensitiveCompare(area) == .orderedSame
                && lesson.sequence.caseInsensitiveCompare(sequence) == .orderedSame
        }
    }

    private var orderedLessons: [CDLesson] {
        lessonsInSequence.sorted { lhs, rhs in
            if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame { return nameCompare == .orderedAscending }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }
    
    /// Automatically recomputes when orderedLessons changes
    private var sectionOrder: [String] {
        let existing = Array(Set(orderedLessons.map { $0.section.trimmed() }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadSectionOrder(for: area, sequence: sequence, existing: existing)
    }

    var body: some View {
        List {
            // If there are sections, present as structural sections.
            if !sectionOrder.isEmpty {
                ForEach(sectionOrder, id: \.self) { sh in
                    let items = orderedLessons.filter { $0.section.trimmed() == sh }
                    if !items.isEmpty {
                        Section(header: Text(sh)) {
                            ForEach(items, id: \.id) { lesson in
                                LessonRow(lesson: lesson, secondaryTextStyle: .areaAndSequence, showTagIcon: true)
                            }
                            .onMove(perform: canReorderLessons ? { source, destination in
                                // IMPORTANT: onMove needs a single ordered subset.
                                // Here we reorder within the section section only.
                                onMoveLesson(source, destination, items)
                            } : nil)
                        }
                    }
                }

                // Lessons with no section go at the end (optional section)
                let noSub = orderedLessons.filter { $0.section.trimmed().isEmpty }
                if !noSub.isEmpty {
                    Section(header: Text("Other")) {
                        ForEach(noSub, id: \.id) { lesson in
                            LessonRow(lesson: lesson, secondaryTextStyle: .areaAndSequence, showTagIcon: true)
                        }
                        .onMove(perform: canReorderLessons ? { source, destination in
                            onMoveLesson(source, destination, noSub)
                        } : nil)
                    }
                }
            } else {
                // No sections: single list
                ForEach(orderedLessons, id: \.id) { lesson in
                    LessonRow(lesson: lesson, secondaryTextStyle: .areaAndSequence, showTagIcon: true)
                }
                .onMove(perform: canReorderLessons ? { source, destination in
                    onMoveLesson(source, destination, orderedLessons)
                } : nil)
            }
        }
        .listStyle(.inset)
        .contentMargins(.leading, 0, for: .scrollContent)
        .contentMargins(.trailing, 0, for: .scrollContent)
        .navigationTitle(sequence)
    }
}
