import SwiftUI
import CoreData

/// The one lesson picker for linking lessons: to a resource (several), to a
/// Going Out (several) and to a project's work (one). The catalog by area in
/// curriculum order, each area folded away until it is opened or searched,
/// with a check on every chosen lesson. Search matches a lesson's name, area
/// or sequence.
///
/// It is a list with a search field and a title; the caller puts it in a
/// navigation stack (a sheet's, or a form's `NavigationLink`).
struct LessonLinkPicker: View {
    @Environment(\.dependencies) private var dependencies

    /// Several lessons: what is ticked. Nil when one lesson is chosen.
    private let selection: Binding<Set<UUID>>?
    private let chosen: UUID?
    private let onChoose: ((UUID) -> Void)?

    @State private var searchText = ""
    @State private var expandedAreas: Set<String> = []

    /// Several lessons, ticked on and off in `selection`.
    init(selection: Binding<Set<UUID>>) {
        self.selection = selection
        self.chosen = nil
        self.onChoose = nil
    }

    /// One lesson: `onChoose` hears the lesson picked (the caller closes the picker).
    init(chosen: UUID?, onChoose: @escaping (UUID) -> Void) {
        self.selection = nil
        self.chosen = chosen
        self.onChoose = onChoose
    }

    private var allowsMultiple: Bool { selection != nil }

    private var chosenIDs: Set<UUID> {
        if let selection { return selection.wrappedValue }
        return chosen.map { [$0] } ?? []
    }

    private func toggle(_ id: UUID) {
        if let selection {
            if selection.wrappedValue.contains(id) {
                selection.wrappedValue.remove(id)
            } else {
                selection.wrappedValue.insert(id)
            }
        } else {
            onChoose?(id)
        }
    }

    private var groups: [LessonLinkPickerGroup] {
        LessonLinkPickerGroup.groups(from: dependencies.lessonCatalog.sortedByAreaAndSortIndex, matching: searchText)
    }

    var body: some View {
        let groups = self.groups
        List {
            if allowsMultiple, !chosenIDs.isEmpty {
                Section {
                    HStack {
                        Text("\(chosenIDs.count) lesson\(chosenIDs.count == 1 ? "" : "s") linked")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear All") {
                            selection?.wrappedValue = []
                        }
                        .font(.caption)
                    }
                }
            }

            ForEach(groups) { group in
                Section {
                    DisclosureGroup(isExpanded: expansion(for: group)) {
                        ForEach(group.lessons, id: \.objectID) { lesson in
                            row(for: lesson)
                        }
                    } label: {
                        areaLabel(for: group)
                    }
                }
            }

            if groups.isEmpty {
                Text(searchText.isEmpty ? "No lessons yet" : "No matching lessons")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $searchText, prompt: "Search lessons")
        .navigationTitle(allowsMultiple ? "Link to Lessons" : "Choose Lesson")
        .inlineNavigationTitle()
        .onAppear {
            // Open the areas that already hold a chosen lesson.
            let chosen = chosenIDs
            expandedAreas = Set(groups.filter { group in
                group.lessons.contains { $0.id.map(chosen.contains) ?? false }
            }.map(\.area))
        }
    }

    private func expansion(for group: LessonLinkPickerGroup) -> Binding<Bool> {
        Binding(
            get: { !searchText.isEmpty || expandedAreas.contains(group.area) },
            set: { isOpen in
                if isOpen {
                    expandedAreas.insert(group.area)
                } else {
                    expandedAreas.remove(group.area)
                }
            }
        )
    }

    private func areaLabel(for group: LessonLinkPickerGroup) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColors.color(forArea: group.area))
                .frame(width: 8, height: 8)
            Text(group.area.isEmpty ? "No Area" : group.area)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("\(group.lessons.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func row(for lesson: CDLesson) -> some View {
        let isChosen = lesson.id.map(chosenIDs.contains) ?? false
        return Button {
            guard let id = lesson.id else { return }
            toggle(id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(lesson.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !lesson.sequence.isEmpty {
                        Text(lesson.sequence)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// One area's lessons in the picker, in the catalog's order.
struct LessonLinkPickerGroup: Identifiable {
    let area: String
    let lessons: [CDLesson]

    var id: String { area }

    /// The lessons matching `searchText` (name, area or sequence; all when
    /// empty), grouped by trimmed area in the order the areas first appear.
    static func groups(from lessons: [CDLesson], matching searchText: String) -> [LessonLinkPickerGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var order: [String] = []
        var byArea: [String: [CDLesson]] = [:]
        for lesson in lessons {
            if !query.isEmpty,
               !lesson.name.localizedCaseInsensitiveContains(query),
               !lesson.area.localizedCaseInsensitiveContains(query),
               !lesson.sequence.localizedCaseInsensitiveContains(query) {
                continue
            }
            let area = lesson.area.trimmingCharacters(in: .whitespaces)
            if byArea[area] == nil { order.append(area) }
            byArea[area, default: []].append(lesson)
        }
        return order.map { LessonLinkPickerGroup(area: $0, lessons: byArea[$0] ?? []) }
    }
}
