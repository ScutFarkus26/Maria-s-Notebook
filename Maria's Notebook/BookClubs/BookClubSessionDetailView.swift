import SwiftUI
import SwiftData

struct BookClubSessionDetailView: View {
    let session: BookClubSession

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var students: [Student]
    @Query(sort: [SortDescriptor(\Lesson.name)]) private var lessons: [Lesson]
    
    // NEW: Query all work contracts to filter locally
    @Query private var allWorkContracts: [WorkContract]

    @State private var showLessonPickerForContract: WorkContract? = nil
    
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }

    // Filter contracts relevant to this session
    private var sessionContracts: [WorkContract] {
        let sid = session.id.uuidString
        return allWorkContracts.filter {
            $0.sourceContextType == .bookClubSession && $0.sourceContextID == sid
        }
    }

    private func studentName(for sid: String) -> String {
        if let uuid = UUID(uuidString: sid), let s = studentsByID[uuid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    private var groupedByStudent: [(id: String, items: [WorkContract])] {
        let items = sessionContracts
        var buckets: [String: [WorkContract]] = [:]
        var order: [String] = []
        
        // Use the session's contract list to determine order if possible,
        // otherwise sort by student ID
        for c in items {
            let sid = c.studentID
            if buckets[sid] == nil {
                order.append(sid)
                buckets[sid] = []
            }
            buckets[sid]?.append(c)
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
                    ContentUnavailableView("No Work Contracts", systemImage: "doc.text", description: Text("No work contracts are linked to this session."))
                } else {
                    ForEach(groupedByStudent, id: \.id) { bucket in
                        Section(header: Text(studentName(for: bucket.id)).font(.headline)) {
                            ForEach(bucket.items, id: \.id) { contract in
                                contractRow(contract)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Self.df.string(from: session.meetingDate))
        .sheet(item: $showLessonPickerForContract) { targetContract in
            BookClubLessonPickerSheet(
                viewModel: {
                    let initialIDs = Set([UUID(uuidString: targetContract.studentID)].compactMap { $0 })
                    let vm = LessonPickerViewModel(selectedStudentIDs: initialIDs)
                    vm.configure(lessons: lessons, students: students)
                    return vm
                }()
            ) { chosenID in
                if let chosenID {
                    targetContract.lessonID = chosenID.uuidString
                    _ = saveCoordinator.save(modelContext, reason: "Link contract to lesson")
                }
            }
        }
    }

    @ViewBuilder
    private func contractRow(_ contract: WorkContract) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                // Title (Role)
                TextField("Title", text: Binding(
                    get: { contract.scheduledNote ?? "" },
                    set: { contract.scheduledNote = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
                Spacer()
                
                // Status Picker
                Picker("Status", selection: Bindable(contract).status) {
                    Text("Active").tag(WorkStatus.active)
                    Text("Review").tag(WorkStatus.review)
                    Text("Complete").tag(WorkStatus.complete)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                
                // Due Date
                DatePicker("Due", selection: Binding(
                    get: { contract.scheduledDate ?? Date() },
                    set: { contract.scheduledDate = $0 }
                ), displayedComponents: .date)
                .labelsHidden()
            }

            // Linked Lesson display
            HStack(spacing: 8) {
                if let uuid = UUID(uuidString: contract.lessonID), let l = lessonsByID[uuid] {
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
                    showLessonPickerForContract = contract
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
private struct BookClubLessonPickerSheet: View {
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
