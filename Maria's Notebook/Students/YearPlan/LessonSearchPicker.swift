import SwiftUI
import CoreData

struct LessonSearchPicker: View {
    @Binding var selectedLesson: CDLesson?

    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDLesson.subject, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.group, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.orderInGroup, ascending: true)
        ]
    ) private var allLessons: FetchedResults<CDLesson>

    @State private var searchText = ""

    private var filteredLessons: [CDLesson] {
        if searchText.isEmpty { return Array(allLessons) }
        let query = searchText.lowercased()
        return allLessons.filter {
            $0.name.lowercased().contains(query)
                || $0.subject.lowercased().contains(query)
                || $0.group.lowercased().contains(query)
        }
    }

    private var groupedBySubject: [(subject: String, groups: [(group: String, lessons: [CDLesson])])] {
        let bySubject = Dictionary(grouping: filteredLessons) { $0.subject }
        return bySubject.keys.sorted().map { subject in
            let subjectLessons = bySubject[subject] ?? []
            let byGroup = Dictionary(grouping: subjectLessons) { $0.group }
            let groups = byGroup.keys.sorted().map { group in
                (group: group, lessons: (byGroup[group] ?? []).sorted { $0.orderInGroup < $1.orderInGroup })
            }
            return (subject: subject, groups: groups)
        }
    }

    var body: some View {
        List {
            ForEach(groupedBySubject, id: \.subject) { subjectSection in
                Section {
                    ForEach(subjectSection.groups, id: \.group) { groupSection in
                        DisclosureGroup {
                            ForEach(groupSection.lessons, id: \.id) { lesson in
                                lessonRow(lesson)
                            }
                        } label: {
                            groupLabel(subjectSection.subject, group: groupSection.group)
                        }
                    }
                } header: {
                    Text(subjectSection.subject)
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
                    if !lesson.subheading.isEmpty {
                        Text(lesson.subheading)
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

    private func groupLabel(_ subject: String, group: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppColors.color(forSubject: subject))
                .frame(width: 8, height: 8)
            Text(group)
                .font(.subheadline.weight(.medium))
        }
    }
}
