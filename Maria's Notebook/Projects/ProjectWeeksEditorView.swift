// swiftlint:disable file_length
import SwiftUI
import CoreData

struct ProjectWeeksEditorView: View {
    let club: Project
    let showHeader: Bool

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Performance: Use filtered query instead of loading all weeks
    @FetchRequest private var weeks: FetchedResults<CDProjectTemplateWeek>

    @State private var editingWeek: ProjectTemplateWeek?

    init(club: Project, showHeader: Bool = true) {
        self.club = club
        self.showHeader = showHeader
        // Filter weeks by projectID at query level
        let projectIDString = (club.id ?? UUID()).uuidString
        _weeks = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDProjectTemplateWeek.weekIndex, ascending: true)],
            predicate: NSPredicate(format: "projectID == %@", projectIDString)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                HStack {
                    Text("Weeks")
                        .font(.headline)
                    Spacer()
                    Button(action: addWeek) { Label("Add Week", systemImage: "plus") }
                }
            } else {
                HStack {
                    Spacer()
                    Button(action: addWeek) { Label("Add Week", systemImage: "plus") }
                }
            }
            if weeks.isEmpty {
                ContentUnavailableView(
                    "No Weeks",
                    systemImage: "calendar",
                    description: Text("Add Week to start building your template.")
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(weeks), id: \.objectID) { week in
                        Button { editingWeek = week } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Week \(week.weekIndex)")
                                    .font(.body.weight(.semibold))
                                if !week.readingRange.trimmed().isEmpty {
                                    Text("— \(week.readingRange)")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Delete", role: .destructive) { delete(week) } }
                        Divider()
                    }
                }
            }
        }
        .sheet(item: $editingWeek) { week in
            ProjectWeekEditorView(club: club, week: week) { editingWeek = nil }
        }
    }

    private func addWeek() {
        let nextIndex = (weeks.map(\.weekIndex).max() ?? 0) + 1
        let w = CDProjectTemplateWeek(context: modelContext)
        w.projectID = (club.id ?? UUID()).uuidString
        w.weekIndex = nextIndex
        if w.agendaItems.isEmpty { w.agendaItems = ["Go over work from last week"] }
        saveCoordinator.save(modelContext, reason: "Add project template week")
        editingWeek = w
    }

    private func delete(_ week: ProjectTemplateWeek) {
        // Use the week's relationship to get its role assignments
        let assignments = (week.roleAssignments?.allObjects as? [CDProjectWeekRoleAssignment]) ?? []
        for a in assignments { modelContext.delete(a) }
        modelContext.delete(week)
        saveCoordinator.save(modelContext, reason: "Delete project template week")
    }
}

// NOTE: ProjectWeekEditorView is defined in ProjectWeekEditorView.swift

struct InlineLessonPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""

    let lessons: [Lesson]
    var onChosen: (UUID?) -> Void

    init(lessons: [Lesson], onChosen: @escaping (UUID?) -> Void) {
        self.lessons = lessons
        self.onChosen = onChosen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Lesson")
                .font(.title3).fontWeight(.semibold)
            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(filteredLessons, id: \.objectID) { lesson in
                    Button {
                        onChosen(lesson.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                                let subtitle: String = {
                                    switch (lesson.subject.isEmpty, lesson.group.isEmpty) {
                                    case (false, false): return "\(lesson.subject) • \(lesson.group)"
                                    case (false, true): return lesson.subject
                                    case (true, false): return lesson.group
                                    default: return ""
                                    }
                                }()
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
    #endif
    #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    private var filteredLessons: [Lesson] {
        let q = search.trimmed()
        if q.isEmpty { return lessons }
        return lessons.filter { l in
            l.name.localizedCaseInsensitiveContains(q) ||
            l.subject.localizedCaseInsensitiveContains(q) ||
            l.group.localizedCaseInsensitiveContains(q)
        }
    }
}
