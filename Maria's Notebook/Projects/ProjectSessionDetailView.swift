import SwiftUI
import SwiftData

struct ProjectSessionDetailView: View {
    let session: ProjectSession

    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }
    @Query(sort: [SortDescriptor(\Lesson.name)]) private var lessons: [Lesson]

    // NEW: Query all work models to filter locally
    @Query private var allWorkModels: [WorkModel]

    @State private var showLessonPickerForWork: WorkModel? = nil
    @State private var showSelectionSheetForStudent: String? = nil
    @State private var showAddWorkSheet: Bool = false

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var studentsByID: [UUID: Student] { Dictionary(students.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }

    // Filter work models relevant to this session
    private var sessionWorkModels: [WorkModel] {
        let sid = session.id.uuidString
        return allWorkModels.filter { work in
            let contextType = work.sourceContextType
            return (contextType == .projectSession || contextType == .bookClubSession) && work.sourceContextID == sid
        }
    }

    private func studentName(for sid: String) -> String {
        if let uuid = UUID(uuidString: sid), let s = studentsByID[uuid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    /// Works grouped by student (for uniform mode or assigned works in choice mode)
    private var groupedByStudent: [(id: String, items: [WorkModel])] {
        // For choice mode, only include works that have participants
        let items = session.assignmentMode == .choice
            ? sessionWorkModels.filter { !$0.isOffered }
            : sessionWorkModels

        var buckets: [String: [WorkModel]] = [:]
        var order: [String] = []

        for work in items {
            // For works with participants, group by each participant
            let participantIDs = work.selectedStudentIDs
            if participantIDs.isEmpty {
                // Fallback to studentID for backward compatibility
                let sid = work.studentID
                if !sid.isEmpty {
                    if buckets[sid] == nil {
                        order.append(sid)
                        buckets[sid] = []
                    }
                    buckets[sid]?.append(work)
                }
            } else {
                for sid in participantIDs {
                    if buckets[sid] == nil {
                        order.append(sid)
                        buckets[sid] = []
                    }
                    buckets[sid]?.append(work)
                }
            }
        }

        // Sort bucket order by student name
        let sortedOrder = order.sorted { id1, id2 in
            studentName(for: id1) < studentName(for: id2)
        }

        return sortedOrder.map { (id: $0, items: buckets[$0] ?? []) }
    }

    /// Offered works (no participants yet) for choice mode
    private var offeredWorks: [WorkModel] {
        sessionWorkModels.filter { $0.isOffered }
    }

    /// Project member IDs for showing selection status
    private var projectMemberIDs: [String] {
        session.project?.memberStudentIDs ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Chapter/Pages", text: Binding(
                        get: { session.chapterOrPages ?? "" },
                        set: { session.chapterOrPages = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Agenda Items")
                            .font(.headline)
                        ForEach(Array(session.agendaItems.enumerated()), id: \.offset) { index, item in
                            HStack {
                                TextField("Agenda item", text: Binding(
                                    get: { session.agendaItems.indices.contains(index) ? session.agendaItems[index] : "" },
                                    set: {
                                        if session.agendaItems.indices.contains(index) {
                                            session.agendaItems[index] = $0
                                        }
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                Button(role: .destructive) {
                                    if session.agendaItems.indices.contains(index) {
                                        session.agendaItems.remove(at: index)
                                        try? modelContext.save()
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button {
                            session.agendaItems.append("")
                            try? modelContext.save()
                        } label: {
                            Label("Add Item", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal)
            .onDisappear {
                try? modelContext.save()
            }

            List {
                // Assignment mode indicator
                if session.assignmentMode == .choice {
                    Section {
                        HStack {
                            Label("Student Choice", systemImage: "hand.tap")
                            Spacer()
                            Text("Pick \(session.minSelections) of \(offeredWorks.count + sessionWorkModels.filter { !$0.isOffered }.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Choice mode: Show offered works and student selection status
                if session.assignmentMode == .choice {
                    choiceModeContent
                } else {
                    uniformModeContent
                }
            }
        }
        .navigationTitle(Self.df.string(from: session.meetingDate))
        .sheet(item: Binding(
            get: { showSelectionSheetForStudent.map { StudentIDWrapper(id: $0) } },
            set: { showSelectionSheetForStudent = $0?.id }
        )) { wrapper in
            StudentSelectionSheet(
                session: session,
                studentID: wrapper.id,
                studentName: studentName(for: wrapper.id),
                offeredWorks: sessionWorkModels // All session works for selection
            )
        }
        .sheet(item: Binding(
            get: { showLessonPickerForWork.map { WorkIDWrapper(id: $0.id) } },
            set: { wrapper in showLessonPickerForWork = wrapper != nil ? allWorkModels.first { $0.id == wrapper!.id } : nil }
        )) { wrapper in
            if let targetWork = allWorkModels.first(where: { $0.id == wrapper.id }) {
                ProjectLessonPickerSheet(
                    viewModel: {
                        let initialIDs = Set([UUID(uuidString: targetWork.studentID)].compactMap { $0 })
                        let vm = LessonPickerViewModel(selectedStudentIDs: initialIDs)
                        vm.configure(lessons: lessons, students: students)
                        return vm
                    }()
                ) { chosenID in
                    if let _ = chosenID {
                        // WorkModel is writable but editing is disabled for now
                    }
                }
            }
        }
        .sheet(isPresented: $showAddWorkSheet) {
            AddWorkOfferSheet(session: session)
        }
    }
    
    private struct WorkIDWrapper: Identifiable {
        let id: UUID
    }

    private struct StudentIDWrapper: Identifiable {
        let id: String
    }

    // MARK: - Choice Mode Content

    @ViewBuilder
    private var choiceModeContent: some View {
        // Offered works section
        Section("Offered Works") {
            ForEach(offeredWorks) { work in
                offeredWorkRow(work)
            }

            Button {
                showAddWorkSheet = true
            } label: {
                Label("Add Work Offer", systemImage: "plus.circle.fill")
            }
        }

        // Student selection status
        Section("Student Selections") {
            ForEach(projectMemberIDs.sorted { studentName(for: $0) < studentName(for: $1) }, id: \.self) { studentID in
                studentSelectionRow(studentID: studentID)
            }
        }
    }

    @ViewBuilder
    private func offeredWorkRow(_ work: WorkModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(work.title.isEmpty ? "Untitled" : work.title)
                    .font(.headline)
                Spacer()
                let count = work.selectedStudentIDs.count
                Label("\(count) selected", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !work.notes.isEmpty {
                Text(work.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let due = work.dueAt {
                Label {
                    Text(due, format: Date.FormatStyle().month().day())
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func studentSelectionRow(studentID: String) -> some View {
        let selectedWorks = sessionWorkModels.filter { work in
            (work.participants ?? []).contains { $0.studentID == studentID }
        }
        let count = selectedWorks.count
        let min = session.minSelections
        let isComplete = count >= min

        Button {
            showSelectionSheetForStudent = studentID
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentName(for: studentID))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !selectedWorks.isEmpty {
                        Text(selectedWorks.map { $0.title.isEmpty ? "Untitled" : $0.title }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("\(count)/\(min)")
                        .font(.caption)
                        .foregroundStyle(isComplete ? .green : .orange)
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isComplete ? .green : .orange)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Uniform Mode Content

    @ViewBuilder
    private var uniformModeContent: some View {
        if groupedByStudent.isEmpty {
            ContentUnavailableView("No Work", systemImage: "doc.text", description: Text("No work items are linked to this session."))
        } else {
            ForEach(groupedByStudent, id: \.id) { bucket in
                Section(header: Text(studentName(for: bucket.id)).font(.headline)) {
                    ForEach(bucket.items, id: \.id) { work in
                        workRow(work)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func workRow(_ work: WorkModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                // Title (Role) - Display only
                TextField("Title", text: Binding(
                    get: { work.scheduledNote ?? "" },
                    set: { _ in }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
                
                Spacer()
                
                // Status Picker - Display only
                Picker("Status", selection: Binding(
                    get: { work.status },
                    set: { _ in }
                )) {
                    Text("Active").tag(WorkStatus.active)
                    Text("Review").tag(WorkStatus.review)
                    Text("Complete").tag(WorkStatus.complete)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(true)
                
                // Due Date - Display only
                if let dueAt = work.dueAt {
                    DatePicker("Due", selection: .constant(dueAt), displayedComponents: .date)
                        .labelsHidden()
                        .disabled(true)
                } else {
                    Text("No due date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Linked Lesson display
            HStack(spacing: 8) {
                if let uuid = UUID(uuidString: work.lessonID), let l = lessonsByID[uuid] {
                    Text("Linked: \(l.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No lesson linked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showLessonPickerForWork = work
                } label: {
                    Label("Change Lesson", systemImage: "book")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.vertical, 6)
    }

    private static let df: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .medium; return df
    }()
}

// A minimal wrapper that reuses LessonPickerViewModel to choose a single lesson
private struct ProjectLessonPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let viewModel: LessonPickerViewModel
    var onChosen: (UUID?) -> Void

    @State private var search: String = ""
    @Query(sort: [SortDescriptor(\Lesson.name)]) private var lessons: [Lesson]

    init(viewModel: LessonPickerViewModel, onChosen: @escaping (UUID?) -> Void) {
        self.viewModel = viewModel
        self.onChosen = onChosen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Lesson")
                .font(.title3).fontWeight(.semibold)
            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(filteredLessons) { l in
                    Button {
                        onChosen(l.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(l.name)
                            Spacer()
                            if viewModel.selectedLessonID == l.id { Image(systemName: "checkmark") }
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

// MARK: - Add Work Offer Sheet

private struct AddWorkOfferSheet: View {
    let session: ProjectSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var title: String = ""
    @State private var instructions: String = ""
    @State private var dueDate: Date

    init(session: ProjectSession) {
        self.session = session
        _dueDate = State(initialValue: session.meetingDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Work Offer")
                .font(.title3).fontWeight(.semibold)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $instructions)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            }

            DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { addWork() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 400)
        .presentationSizingFitted()
    #else
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    #endif
    }

    private func addWork() {
        let service = SessionWorkAssignmentService(context: modelContext)
        do {
            try service.createOfferedWork(
                session: session,
                title: title,
                instructions: instructions,
                dueDate: dueDate
            )
            _ = saveCoordinator.save(modelContext, reason: "Add work offer to session")
        } catch {
            #if DEBUG
            print("⚠️ Failed to add work offer: \(error)")
            #endif
        }
        dismiss()
    }
}
