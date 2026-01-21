import SwiftUI
import SwiftData

struct ProjectSessionDetailView: View {
    let session: ProjectSession

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var students: [Student] { studentsRaw.uniqueByID }
    @Query(sort: [SortDescriptor(\Lesson.name)]) private var lessons: [Lesson]

    // NEW: Query all work models to filter locally
    @Query private var allWorkModels: [WorkModel]

    @State private var showLessonPickerForWork: WorkModel? = nil

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

    private var groupedByStudent: [(id: String, items: [WorkModel])] {
        let items = sessionWorkModels
        var buckets: [String: [WorkModel]] = [:]
        var order: [String] = []
        
        // Use the session's work list to determine order if possible,
        // otherwise sort by student ID
        for work in items {
            let sid = work.studentID
            if buckets[sid] == nil {
                order.append(sid)
                buckets[sid] = []
            }
            buckets[sid]?.append(work)
        }
        
        // Sort bucket order by student name
        let sortedOrder = order.sorted { id1, id2 in
            studentName(for: id1) < studentName(for: id2)
        }
        
        return sortedOrder.map { (id: $0, items: buckets[$0] ?? []) }
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
        }
        .navigationTitle(Self.df.string(from: session.meetingDate))
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
    }
    
    private struct WorkIDWrapper: Identifiable {
        let id: UUID
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
                DatePicker("Due", selection: Binding(
                    get: { work.dueAt ?? Date() },
                    set: { _ in }
                ), displayedComponents: .date)
                .labelsHidden()
                .disabled(true)
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
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return lessons }
        return lessons.filter { l in
            l.name.localizedCaseInsensitiveContains(q) ||
            l.subject.localizedCaseInsensitiveContains(q) ||
            l.group.localizedCaseInsensitiveContains(q)
        }
    }
}
