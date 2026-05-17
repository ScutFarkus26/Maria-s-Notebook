import SwiftUI
import CoreData

struct LessonSearchPicker: View {
    @Binding var selectedLesson: CDLesson?

    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.sequence, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true)
        ]
    ) private var allLessons: FetchedResults<CDLesson>

    @State private var searchText = ""

    private var filteredLessons: [CDLesson] {
        if searchText.isEmpty { return Array(allLessons) }
        let query = searchText.lowercased()
        return allLessons.filter {
            $0.name.lowercased().contains(query)
                || $0.area.lowercased().contains(query)
                || $0.sequence.lowercased().contains(query)
        }
    }

    private var groupedByArea: [(area: String, groups: [(sequence: String, lessons: [CDLesson])])] {
        let byArea = Dictionary(grouping: filteredLessons) { $0.area }
        return byArea.keys.sorted().map { area in
            let areaLessons = byArea[area] ?? []
            let bySequence = Dictionary(grouping: areaLessons) { $0.sequence }
            let groups = bySequence.keys.sorted().map { sequence in
                (sequence: sequence, lessons: (bySequence[sequence] ?? []).sorted { $0.orderInSequence < $1.orderInSequence })
            }
            return (area: area, groups: groups)
        }
    }

    var body: some View {
        List {
            ForEach(groupedByArea, id: \.area) { areaSection in
                Section {
                    ForEach(areaSection.groups, id: \.sequence) { groupSection in
                        DisclosureGroup {
                            ForEach(groupSection.lessons, id: \.id) { lesson in
                                lessonRow(lesson)
                            }
                        } label: {
                            groupLabel(areaSection.area, sequence: groupSection.sequence)
                        }
                    }
                } header: {
                    Text(areaSection.area)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search lessons...")
        .navigationTitle("Choose Lesson")
    }

    private func lessonRow(_ lesson: CDLesson) -> some View {
        Button {
            selectedLesson = lesson
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if !lesson.section.isEmpty {
                        Text(lesson.section)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if lesson.id == selectedLesson?.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accent)
                }
            }
        }
    }

    private func groupLabel(_ area: String, sequence: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppColors.color(forArea: area))
                .frame(width: 8, height: 8)
            Text(sequence)
                .font(.subheadline.weight(.medium))
        }
    }
}
