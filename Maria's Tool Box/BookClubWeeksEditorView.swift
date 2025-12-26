import SwiftUI
import SwiftData

struct BookClubWeeksEditorView: View {
    let club: BookClub
    let showHeader: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor<BookClubTemplateWeek>(\.weekIndex, order: .forward)]) private var allWeeks: [BookClubTemplateWeek]
    @Query(sort: [SortDescriptor(\BookClubWeekRoleAssignment.createdAt, order: .forward)]) private var allRoleAssignments: [BookClubWeekRoleAssignment]

    @State private var editingWeek: BookClubTemplateWeek? = nil

    init(club: BookClub, showHeader: Bool = true) {
        self.club = club
        self.showHeader = showHeader
    }

    private var weeks: [BookClubTemplateWeek] {
        allWeeks.filter { $0.bookClubID == club.id }
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
                ContentUnavailableView("No Weeks", systemImage: "calendar", description: Text("Add Week to start building your template."))
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(weeks, id: \.id) { week in
                        Button { editingWeek = week } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Week \(week.weekIndex)")
                                    .font(.body.weight(.semibold))
                                if !week.readingRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            BookClubWeekEditorView(club: club, week: week) { editingWeek = nil }
        }
    }

    private func addWeek() {
        let nextIndex = (weeks.map { $0.weekIndex }.max() ?? 0) + 1
        let w = BookClubTemplateWeek(bookClubID: club.id, weekIndex: nextIndex)
        if w.agendaItems.isEmpty { w.agendaItems = ["Go over work from last week"] }
        modelContext.insert(w)
        _ = saveCoordinator.save(modelContext, reason: "Add book club template week")
        editingWeek = w
    }

    private func delete(_ week: BookClubTemplateWeek) {
        let assigns = allRoleAssignments.filter { $0.weekID == week.id }
        for a in assigns { modelContext.delete(a) }
        modelContext.delete(week)
        _ = saveCoordinator.save(modelContext, reason: "Delete book club template week")
    }
}

struct BookClubWeekEditorView: View, Identifiable {
    var id: UUID { week.id }
    let club: BookClub
    let week: BookClubTemplateWeek
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\Student.firstName, order: .forward), SortDescriptor(\Student.lastName, order: .forward)]) private var students: [Student]
    @Query(sort: [SortDescriptor(\BookClubRole.createdAt, order: .forward)]) private var allRoles: [BookClubRole]
    @Query(sort: [SortDescriptor(\BookClubWeekRoleAssignment.createdAt, order: .forward)]) private var allRoleAssignments: [BookClubWeekRoleAssignment]
    @Query(sort: [SortDescriptor(\Lesson.name, order: .forward)]) private var allLessons: [Lesson]

    @State private var readingRange: String
    @State private var agenda: [String]
    @State private var workInstructions: String
    @State private var linkedLessonIDs: [String] = []

    @State private var pickingLessonForWeek: Bool = false
    @State private var viewingLesson: Lesson? = nil

    init(club: BookClub, week: BookClubTemplateWeek, onDone: @escaping () -> Void) {
        self.club = club
        self.week = week
        self.onDone = onDone
        _readingRange = State(initialValue: week.readingRange)
        _agenda = State(initialValue: week.agendaItems)
        _workInstructions = State(initialValue: week.workInstructions)
        _linkedLessonIDs = State(initialValue: week.linkedLessonIDs)
    }

    private var roles: [BookClubRole] {
        allRoles.filter { $0.bookClubID == club.id }
    }

    private var clubMembers: [Student] {
        let ids = Set(club.memberStudentIDs.compactMap(UUID.init))
        return students.filter { ids.contains($0.id) }.sorted { StudentFormatter.displayName(for: $0) < StudentFormatter.displayName(for: $1) }
    }

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: allLessons.map { ($0.id, $0) }) }

    private var linkedLessons: [Lesson] {
        linkedLessonIDs.compactMap { UUID(uuidString: $0) }.compactMap { lessonsByID[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(week.weekIndex)")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // 1. Reading
                    sectionCard("Reading", systemImage: "book") {
                        TextField("Reading range (e.g., Chapters 8–14)", text: $readingRange)
                            .textFieldStyle(.roundedBorder)
                    }

                    // 2. Presentations
                    sectionCard("Presentations", systemImage: "easel") {
                        if linkedLessonIDs.isEmpty {
                            Text("No presentations linked.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(linkedLessons) { lesson in
                                    HStack {
                                        Button {
                                            viewingLesson = lesson
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "info.circle").font(.caption)
                                                Text(lesson.name).fontWeight(.medium)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.blue)

                                        Spacer()
                                        
                                        Button {
                                            if let idx = linkedLessonIDs.firstIndex(of: lesson.id.uuidString) {
                                                linkedLessonIDs.remove(at: idx)
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary.opacity(0.8))
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(8)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        
                        Button("Add Presentation") { pickingLessonForWeek = true }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                    }

                    // 3. Work Packet
                    sectionCard("Work Packet Instructions", systemImage: "doc.text") {
                        Text("Enter instructions for the weekly student packet (e.g. 'Complete role sheet and find 5 vocab words').")
                            .font(.caption).foregroundStyle(.secondary)
                        
                        TextEditor(text: $workInstructions)
                            .frame(minHeight: 80)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                    }

                    // 4. Agenda
                    sectionCard("Meeting Agenda", systemImage: "list.bullet") {
                        editableStringList($agenda, placeholder: "Agenda item")
                    }

                    // 5. Roles
                    sectionCard("Weekly Role Schedule", systemImage: "person.2") {
                        if clubMembers.isEmpty {
                            Text("No members in this club.")
                                .foregroundStyle(.secondary)
                        } else if roles.isEmpty {
                            Text("No roles defined. Add roles first.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(clubMembers, id: \.id) { student in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(StudentFormatter.displayName(for: student))
                                        Spacer(minLength: 12)
                                        Picker("Role", selection: Binding(
                                            get: { currentRoleID(for: student.id) },
                                            set: { setRoleID($0, for: student.id) }
                                        )) {
                                            Text("—").tag(Optional<UUID>(nil))
                                            ForEach(roles, id: \.id) { role in
                                                Text(role.title).tag(Optional(role.id))
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                        .opacity(0.15)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider()
                .padding(.top, 4)
            // Bottom actions
            HStack {
                Spacer()
                Button("Cancel") { onDone(); dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
    #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    #endif
        .sheet(isPresented: $pickingLessonForWeek) {
            InlineLessonPickerSheet(lessons: allLessons) { chosenID in
                if let uuid = chosenID {
                    linkedLessonIDs.append(uuid.uuidString)
                }
            }
        }
        .sheet(item: $viewingLesson) { lesson in
            LessonDetailView(lesson: lesson, onSave: { _ in
                _ = saveCoordinator.save(modelContext, reason: "Update lesson details from book club editor")
            }, onDone: {
                viewingLesson = nil
            })
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func editableStringList(_ binding: Binding<[String]>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(binding.wrappedValue.enumerated()), id: \.offset) { idx, _ in
                HStack {
                    TextField(placeholder, text: Binding(
                        get: { binding.wrappedValue[idx] },
                        set: { binding.wrappedValue[idx] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) { binding.wrappedValue.remove(at: idx) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
            Button { binding.wrappedValue.append("") } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Role schedule helpers
    private func currentRoleID(for studentID: UUID) -> UUID? {
        let sid = studentID.uuidString
        return allRoleAssignments.first { $0.weekID == week.id && $0.studentID == sid }?.roleID
    }

    private func setRoleID(_ roleID: UUID?, for studentID: UUID) {
        let sid = studentID.uuidString
        if let existing = allRoleAssignments.first(where: { $0.weekID == week.id && $0.studentID == sid }) {
            if let roleID { existing.roleID = roleID } else { modelContext.delete(existing) }
        } else if let roleID {
            let a = BookClubWeekRoleAssignment(weekID: week.id, studentID: sid, roleID: roleID)
            modelContext.insert(a)
        }
    }

    private func save() {
        week.readingRange = readingRange
        week.agendaItems = agenda
        week.workInstructions = workInstructions
        week.linkedLessonIDs = linkedLessonIDs
        _ = saveCoordinator.save(modelContext, reason: "Save book club template week")
        onDone(); dismiss()
    }
}

private struct InlineLessonPickerSheet: View {
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
                ForEach(filteredLessons) { lesson in
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
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return lessons }
        return lessons.filter { l in
            l.name.localizedCaseInsensitiveContains(q) ||
            l.subject.localizedCaseInsensitiveContains(q) ||
            l.group.localizedCaseInsensitiveContains(q)
        }
    }
}
