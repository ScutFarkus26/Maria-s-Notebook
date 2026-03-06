import SwiftUI

/// Compact lesson picker for linking resources to lessons.
/// Groups lessons by subject and allows multi-select with search.
struct ResourceLessonPicker: View {
    let allLessons: [Lesson]
    @Binding var selectedLessonIDs: Set<UUID>

    @State private var searchText = ""
    @State private var expandedSubjects: Set<String> = []

    private var groupedLessons: [(subject: String, lessons: [Lesson])] {
        let filtered: [Lesson]
        if searchText.isEmpty {
            filtered = allLessons
        } else {
            let query = searchText.lowercased()
            filtered = allLessons.filter {
                $0.name.lowercased().contains(query) ||
                $0.subject.lowercased().contains(query)
            }
        }

        let grouped = Dictionary(grouping: filtered) {
            $0.subject.trimmingCharacters(in: .whitespaces)
        }

        return grouped.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }.compactMap { subject in
            guard let lessons = grouped[subject], !lessons.isEmpty else { return nil }
            return (subject: subject, lessons: lessons.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Selected count
            if !selectedLessonIDs.isEmpty {
                HStack {
                    Text("\(selectedLessonIDs.count) lesson\(selectedLessonIDs.count == 1 ? "" : "s") linked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All") {
                        selectedLessonIDs.removeAll()
                    }
                    .font(.caption)
                }
            }

            // Search
            TextField("Search lessons...", text: $searchText)
                .font(.subheadline)

            // Grouped lessons
            ForEach(groupedLessons, id: \.subject) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedSubjects.contains(group.subject) || !searchText.isEmpty },
                        set: { newValue in
                            if newValue {
                                expandedSubjects.insert(group.subject)
                            } else {
                                expandedSubjects.remove(group.subject)
                            }
                        }
                    )
                ) {
                    ForEach(group.lessons) { lesson in
                        Button {
                            if selectedLessonIDs.contains(lesson.id) {
                                selectedLessonIDs.remove(lesson.id)
                            } else {
                                selectedLessonIDs.insert(lesson.id)
                            }
                        } label: {
                            HStack {
                                Text(lesson.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if selectedLessonIDs.contains(lesson.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(group.subject)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(group.lessons.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if groupedLessons.isEmpty && !searchText.isEmpty {
                Text("No matching lessons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
