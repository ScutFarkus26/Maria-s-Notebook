import SwiftUI

/// Flat, area-grouped list shown when search is active.
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
            ForEach(groupedByArea, id: \.area) { sequence in
                lessonSection(for: sequence)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func lessonSection(for sequence: (area: String, lessons: [CDLesson])) -> some View {
        Section(sequence.area) {
            ForEach(sequence.lessons) { lesson in
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

    private var groupedByArea: [(area: String, lessons: [CDLesson])] {
        let areas = FilterOrderStore.loadAreaOrder(
            existing: Array(Set(lessons.map { $0.area.trimmed() }.filter { !$0.isEmpty }))
        )
        var result: [(area: String, lessons: [CDLesson])] = areas.compactMap { area in
            let areaLessons = lessons.filter { $0.area.trimmed() == area }
            guard !areaLessons.isEmpty else { return nil }
            return (area, areaLessons)
        }
        // Append lessons with no area at the end
        let noArea = lessons.filter { $0.area.trimmed().isEmpty }
        if !noArea.isEmpty {
            result.append(("Other", noArea))
        }
        return result
    }
}
