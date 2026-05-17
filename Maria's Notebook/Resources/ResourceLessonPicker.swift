import SwiftUI
import CoreData

/// Multi-select lesson picker grouped by area.
/// Shown as a NavigationLink destination inside import/edit sheets.
struct ResourceLessonPicker: View {
    let allLessons: [CDLesson]
    @Binding var selectedLessonIDs: Set<UUID>

    @State private var searchText = ""
    @State private var expandedAreas: Set<String> = []

    private var groupedLessons: [(area: String, lessons: [CDLesson])] {
        let filtered: [CDLesson]
        if searchText.isEmpty {
            filtered = allLessons
        } else {
            let query = searchText.lowercased()
            filtered = allLessons.filter {
                $0.name.lowercased().contains(query) ||
                $0.area.lowercased().contains(query)
            }
        }

        let grouped = Dictionary(grouping: filtered) {
            $0.area.trimmingCharacters(in: .whitespaces)
        }

        return grouped.keys.sorted { (a: String, b: String) -> Bool in
            a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }.compactMap { (area: String) -> (area: String, lessons: [CDLesson])? in
            guard let lessons = grouped[area], !lessons.isEmpty else { return nil }
            return (area: area, lessons: lessons.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        List {
            if !selectedLessonIDs.isEmpty {
                Section {
                    HStack {
                        Text("\(selectedLessonIDs.count) lesson\(selectedLessonIDs.count == 1 ? "" : "s") linked")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear All") {
                            selectedLessonIDs.removeAll()
                        }
                        .font(.caption)
                    }
                }
            }

            ForEach(groupedLessons, id: \.area) { group in
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedAreas.contains(group.area) || !searchText.isEmpty },
                            set: { newValue in
                                if newValue {
                                    expandedAreas.insert(group.area)
                                } else {
                                    expandedAreas.remove(group.area)
                                }
                            }
                        )
                    ) {
                        ForEach(group.lessons, id: \.objectID) { lesson in
                            Button {
                                guard let lessonID = lesson.id else { return }
                                toggleLesson(lessonID)
                            } label: {
                                HStack {
                                    Text(lesson.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if let lessonID = lesson.id, selectedLessonIDs.contains(lessonID) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(group.area.isEmpty ? "Ungrouped" : group.area)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(group.lessons.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if groupedLessons.isEmpty {
                if searchText.isEmpty {
                    Text("No lessons available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No matching lessons")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search lessons")
        .navigationTitle("Link to Lessons")
        .inlineNavigationTitle()
    }

    private func toggleLesson(_ id: UUID) {
        if selectedLessonIDs.contains(id) {
            selectedLessonIDs.remove(id)
        } else {
            selectedLessonIDs.insert(id)
        }
    }
}
