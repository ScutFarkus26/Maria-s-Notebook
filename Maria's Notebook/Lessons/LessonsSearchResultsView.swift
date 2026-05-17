import SwiftUI

/// Flat, subject-grouped list shown when search is active.
/// Replaces the normal hierarchy so results are easy to scan and select.
struct LessonsSearchResultsView: View {
    let lessons: [CDLesson]
    var statusCounts: [UUID: Int]? = nil
    var lastPresentedDates: [UUID: Date]? = nil
    var selectedLessonID: UUID? = nil
    var onSelectLesson: ((CDLesson) -> Void)?
    var onScheduleLesson: ((CDLesson) -> Void)?

    var body: some View {
        if lessons.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No lessons match your search.")
            )
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            ForEach(groupedBySubject, id: \.subject) { group in
                lessonSection(for: group)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func lessonSection(for group: (subject: String, lessons: [CDLesson])) -> some View {
        Section(group.subject) {
            ForEach(group.lessons) { lesson in
                lessonRow(for: lesson)
            }
        }
    }

    @ViewBuilder
    private func lessonRow(for lesson: CDLesson) -> some View {
        let statusCount: Int? = lesson.id.flatMap { statusCounts?[$0] }
        let lastDate: Date? = lesson.id.flatMap { lastPresentedDates?[$0] }
        LessonCompactRow(
            lesson: lesson,
            statusCount: statusCount,
            lastPresentedDate: lastDate,
            isSelected: lesson.id == selectedLessonID
        )
        .listRowSeparator(.hidden)
        .simultaneousGesture(TapGesture().onEnded { onSelectLesson?(lesson) })
        .contextMenu {
            Button {
                onSelectLesson?(lesson)
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
            Button {
                onScheduleLesson?(lesson)
            } label: {
                Label("Plan Presentation", systemImage: "tray.and.arrow.down")
            }
        }
    }

    // MARK: - Grouping

    private var groupedBySubject: [(subject: String, lessons: [CDLesson])] {
        let subjects = FilterOrderStore.loadSubjectOrder(
            existing: Array(Set(lessons.map { $0.subject.trimmed() }.filter { !$0.isEmpty }))
        )
        var result: [(subject: String, lessons: [CDLesson])] = subjects.compactMap { subject in
            let subjectLessons = lessons.filter { $0.subject.trimmed() == subject }
            guard !subjectLessons.isEmpty else { return nil }
            return (subject, subjectLessons)
        }
        // Append lessons with no subject at the end
        let noSubject = lessons.filter { $0.subject.trimmed().isEmpty }
        if !noSubject.isEmpty {
            result.append(("Other", noSubject))
        }
        return result
    }
}
