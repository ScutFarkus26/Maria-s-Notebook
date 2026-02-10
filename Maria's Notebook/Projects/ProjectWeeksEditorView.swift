import SwiftUI
import SwiftData

struct ProjectWeeksEditorView: View {
    let club: Project
    let showHeader: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Performance: Use filtered query instead of loading all weeks
    @Query(sort: [SortDescriptor<ProjectTemplateWeek>(\.weekIndex, order: .forward)]) private var weeks: [ProjectTemplateWeek]

    @State private var editingWeek: ProjectTemplateWeek? = nil

    init(club: Project, showHeader: Bool = true) {
        self.club = club
        self.showHeader = showHeader
        // Filter weeks by projectID at query level
        let projectIDString = club.id.uuidString
        _weeks = Query(
            filter: #Predicate<ProjectTemplateWeek> { $0.projectID == projectIDString },
            sort: [SortDescriptor(\.weekIndex, order: .forward)]
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
                ContentUnavailableView("No Weeks", systemImage: "calendar", description: Text("Add Week to start building your template."))
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(weeks, id: \.id) { week in
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
        let nextIndex = (weeks.map { $0.weekIndex }.max() ?? 0) + 1
        let w = ProjectTemplateWeek(projectID: club.id, weekIndex: nextIndex)
        if w.agendaItems.isEmpty { w.agendaItems = ["Go over work from last week"] }
        modelContext.insert(w)
        _ = saveCoordinator.save(modelContext, reason: "Add project template week")
        editingWeek = w
    }

    private func delete(_ week: ProjectTemplateWeek) {
        // Use the week's relationship to get its role assignments
        for a in week.roleAssignments ?? [] { modelContext.delete(a) }
        modelContext.delete(week)
        _ = saveCoordinator.save(modelContext, reason: "Delete project template week")
    }
}

struct ProjectWeekEditorView: View, Identifiable {
    var id: UUID { week.id }
    let club: Project
    let week: ProjectTemplateWeek
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // Performance: Filter students to only club members at query level
    @Query(sort: [SortDescriptor(\Student.firstName, order: .forward), SortDescriptor(\Student.lastName, order: .forward)]) private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // Performance: Filter roles by projectID at query level
    @Query(sort: [SortDescriptor(\ProjectRole.createdAt, order: .forward)]) private var roles: [ProjectRole]

    // Performance: Keep lessons query for lesson picker (needed for full list)
    @Query(sort: [SortDescriptor(\Lesson.name, order: .forward)]) private var allLessons: [Lesson]

    @State private var readingRange: String
    @State private var agenda: [String]
    @State private var linkedLessonIDs: [String] = []

    // Assignment mode state
    @State private var assignmentMode: SessionAssignmentMode
    @State private var minSelections: Int
    @State private var maxSelections: Int
    @State private var offeredWorks: [TemplateOfferedWork]

    @State private var pickingLessonForWeek: Bool = false
    @State private var viewingLesson: Lesson? = nil

    init(club: Project, week: ProjectTemplateWeek, onDone: @escaping () -> Void) {
        self.club = club
        self.week = week
        self.onDone = onDone
        _readingRange = State(initialValue: week.readingRange)
        _agenda = State(initialValue: week.agendaItems)
        _linkedLessonIDs = State(initialValue: week.linkedLessonIDs)
        _assignmentMode = State(initialValue: week.assignmentMode)
        _minSelections = State(initialValue: week.minSelections > 0 ? week.minSelections : 1)
        _maxSelections = State(initialValue: week.maxSelections > 0 ? week.maxSelections : 2)
        _offeredWorks = State(initialValue: week.offeredWorks)

        // Performance: Filter roles by projectID at query level
        let projectIDString = club.id.uuidString
        _roles = Query(
            filter: #Predicate<ProjectRole> { $0.projectID == projectIDString },
            sort: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }

    private var clubMembers: [Student] {
        let ids = Set(club.memberStudentIDs.compactMap(UUID.init))
        return students.filter { ids.contains($0.id) }.sorted { StudentFormatter.displayName(for: $0) < StudentFormatter.displayName(for: $1) }
    }

    // Performance: Pre-compute role assignment lookup dictionary to avoid N+1 searches
    private var roleAssignmentsByStudentID: [String: ProjectWeekRoleAssignment] {
        Dictionary(
            (week.roleAssignments ?? []).map { ($0.studentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: Lesson] { Dictionary(allLessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }

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

                    // 3. Assignment Mode
                    sectionCard("Assignment Mode", systemImage: "hand.tap") {
                        assignmentModeSection
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

    // MARK: - Assignment Mode Section

    @ViewBuilder
    private var assignmentModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $assignmentMode) {
                ForEach(SessionAssignmentMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(assignmentMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if assignmentMode == .choice {
                choiceModeConfiguration
            }
        }
    }

    @ViewBuilder
    private var choiceModeConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Students pick")
                Stepper("\(minSelections)", value: $minSelections, in: 1...10)
                    .fixedSize()
                Text("of")
                Stepper("\(maxSelections == 0 ? "∞" : "\(maxSelections)")", value: $maxSelections, in: 0...10)
                    .fixedSize()
            }
            .font(.subheadline)

            Divider()

            Text("Offered Works")
                .font(.subheadline).fontWeight(.medium)

            ForEach(Array(offeredWorks.enumerated()), id: \.element.id) { index, work in
                HStack(alignment: .top) {
                    VStack(spacing: 4) {
                        TextField("Title", text: Binding(
                            get: { offeredWorks[index].title },
                            set: { offeredWorks[index].title = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        TextField("Instructions (optional)", text: Binding(
                            get: { offeredWorks[index].instructions },
                            set: { offeredWorks[index].instructions = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    }
                    Button {
                        offeredWorks.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                offeredWorks.append(TemplateOfferedWork())
            } label: {
                Label("Add Work Offer", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)

            if offeredWorks.count < minSelections {
                Text("Add at least \(minSelections) work offers")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.leading, 8)
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
    // Performance: Use pre-computed dictionary for O(1) lookup instead of O(n) search
    private func currentRoleID(for studentID: UUID) -> UUID? {
        let sid = studentID.uuidString
        if let roleIDString = roleAssignmentsByStudentID[sid]?.roleID {
            return UUID(uuidString: roleIDString)
        }
        return nil
    }

    private func setRoleID(_ roleID: UUID?, for studentID: UUID) {
        let sid = studentID.uuidString
        // Use the week's relationship directly instead of querying all assignments
        if let existing = (week.roleAssignments ?? []).first(where: { $0.studentID == sid }) {
            if let roleID { existing.roleID = roleID.uuidString } else { modelContext.delete(existing) }
        } else if let roleID {
            let a = ProjectWeekRoleAssignment(weekID: week.id, studentID: sid, roleID: roleID, week: week)
            modelContext.insert(a)
            week.roleAssignments = (week.roleAssignments ?? []) + [a]
        }
    }

    private func save() {
        week.readingRange = readingRange
        week.agendaItems = agenda
        week.linkedLessonIDs = linkedLessonIDs
        week.assignmentMode = assignmentMode
        week.minSelections = assignmentMode == .choice ? minSelections : 0
        week.maxSelections = assignmentMode == .choice ? maxSelections : 0
        week.offeredWorks = assignmentMode == .choice ? offeredWorks : []
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
        let q = search.trimmed()
        if q.isEmpty { return lessons }
        return lessons.filter { l in
            l.name.localizedCaseInsensitiveContains(q) ||
            l.subject.localizedCaseInsensitiveContains(q) ||
            l.group.localizedCaseInsensitiveContains(q)
        }
    }
}
