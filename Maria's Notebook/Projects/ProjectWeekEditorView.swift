import SwiftUI
import CoreData

// swiftlint:disable:next type_body_length
struct ProjectWeekEditorView: View, Identifiable {
    var id: UUID { week.id ?? UUID() }
    let club: CDProject
    let week: CDProjectTemplateWeek
    var onDone: () -> Void

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // Performance: Filter students to only club members at query level
    @FetchRequest(sortDescriptors: CDStudent.sortByName) private var studentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    // Performance: Filter roles by projectID at query level
    @FetchRequest private var roles: FetchedResults<CDProjectRole>

    // Performance: Keep lessons query for lesson picker (needed for full list)
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]) private var allLessons: FetchedResults<CDLesson>

    @State private var readingRange: String
    @State private var agenda: [String]
    @State private var linkedLessonIDs: [String] = []

    // Assignment mode state
    @State var assignmentMode: SessionAssignmentMode
    @State var minSelections: Int
    @State var maxSelections: Int
    @State var offeredWorks: [TemplateOfferedWork]

    @State private var pickingLessonForWeek: Bool = false
    @State private var viewingLesson: CDLesson?

    init(club: CDProject, week: CDProjectTemplateWeek, onDone: @escaping () -> Void) {
        self.club = club
        self.week = week
        self.onDone = onDone
        _readingRange = State(initialValue: week.readingRange)
        _agenda = State(initialValue: week.agendaItems)
        _linkedLessonIDs = State(initialValue: week.linkedLessonIDs)
        _assignmentMode = State(initialValue: week.assignmentMode)
        _minSelections = State(initialValue: week.minSelections > 0 ? Int(week.minSelections) : 1)
        _maxSelections = State(initialValue: week.maxSelections > 0 ? Int(week.maxSelections) : 2)
        _offeredWorks = State(initialValue: week.offeredWorks)

        // Performance: Filter roles by projectID at query level
        let projectIDString = (club.id ?? UUID()).uuidString
        _roles = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDProjectRole.createdAt, ascending: true)],
            predicate: NSPredicate(format: "projectID == %@", projectIDString)
        )
    }

    private var clubMembers: [CDStudent] {
        let ids = Set(club.memberStudentIDsArray.compactMap(UUID.init))
        return students
            .filter { guard let sid = $0.id else { return false }; return ids.contains(sid) }
            .sorted {
                StudentFormatter.displayName(for: $0) < StudentFormatter.displayName(for: $1)
            }
    }

    // Performance: Pre-compute role assignment lookup dictionary to avoid N+1 searches
    private var roleAssignmentsByStudentID: [String: CDProjectWeekRoleAssignment] {
        let assignments = (week.roleAssignments?.allObjects as? [CDProjectWeekRoleAssignment]) ?? []
        return Dictionary(
            assignments.map { ($0.studentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: CDLesson] {
        Dictionary(
            allLessons.compactMap { l -> (UUID, CDLesson)? in guard let id = l.id else { return nil }; return (id, l) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var linkedLessons: [CDLesson] {
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
                                ForEach(linkedLessons, id: \.objectID) { lesson in
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
                                            if let idx = linkedLessonIDs.firstIndex(of: (lesson.id ?? UUID()).uuidString) {
                                                linkedLessonIDs.remove(at: idx)
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary.opacity(UIConstants.OpacityConstants.heavy))
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(8)
                                    .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
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
                                ForEach(clubMembers, id: \.objectID) { student in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(StudentFormatter.displayName(for: student))
                                        Spacer(minLength: 12)
                                        Picker("Role", selection: Binding(
                                            get: { currentRoleID(for: student.id ?? UUID()) },
                                            set: { setRoleID($0, for: student.id ?? UUID()) }
                                        )) {
                                            Text("—").tag(UUID?(nil))
                                            ForEach(Array(roles), id: \.objectID) { role in
                                                Text(role.title).tag(role.id)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                        .opacity(UIConstants.OpacityConstants.accent)
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
            InlineLessonPickerSheet(lessons: Array(allLessons)) { chosenID in
                if let uuid = chosenID {
                    linkedLessonIDs.append(uuid.uuidString)
                }
            }
        }
        .sheet(item: $viewingLesson) { lesson in
            LessonDetailView(lesson: lesson, onSave: { _ in
                saveCoordinator.save(modelContext, reason: "Update lesson details from book club editor")
            }, onDone: {
                viewingLesson = nil
            })
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
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
                    Button(role: .destructive) {
                        binding.wrappedValue.remove(at: idx)
                    } label: {
                        Image(systemName: "trash")
                    }
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
        let assignments = (week.roleAssignments?.allObjects as? [CDProjectWeekRoleAssignment]) ?? []
        if let existing = assignments.first(where: { $0.studentID == sid }) {
            if let roleID { existing.roleID = roleID.uuidString } else { modelContext.delete(existing) }
        } else if let roleID {
            let a = CDProjectWeekRoleAssignment(context: modelContext)
            a.weekID = (week.id ?? UUID()).uuidString
            a.studentID = sid
            a.roleID = roleID.uuidString
            a.week = week
            week.addToRoleAssignments(a)
        }
    }

    private func save() {
        week.readingRange = readingRange
        week.agendaItems = agenda
        week.linkedLessonIDs = linkedLessonIDs
        week.assignmentMode = assignmentMode
        week.minSelections = assignmentMode == .choice ? Int64(minSelections) : 0
        week.maxSelections = assignmentMode == .choice ? Int64(maxSelections) : 0
        week.offeredWorks = assignmentMode == .choice ? offeredWorks : []
        saveCoordinator.save(modelContext, reason: "Save book club template week")
        onDone(); dismiss()
    }
}
