import SwiftUI
import SwiftData

struct BookClubSessionDetailView: View {
    let session: BookClubSession

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var students: [Student]
    @Query(sort: [SortDescriptor(\Lesson.name)]) private var lessons: [Lesson]

    @State private var showLessonPickerForDeliverable: BookClubDeliverable? = nil
    @State private var lessonPickerVM = LessonPickerViewModel()

    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }

    private func studentName(for sid: String) -> String {
        if let uuid = UUID(uuidString: sid), let s = studentsByID[uuid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    private var groupedByStudent: [(id: String, items: [BookClubDeliverable])] {
        let items = session.deliverables
        var buckets: [String: [BookClubDeliverable]] = [:]
        var order: [String] = []
        for d in items {
            if buckets[d.studentID] == nil { order.append(d.studentID); buckets[d.studentID] = [] }
            buckets[d.studentID]?.append(d)
        }
        return order.map { (id: $0, items: buckets[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(groupedByStudent, id: \.id) { bucket in
                    Section(header: Text(studentName(for: bucket.id)).font(.headline)) {
                        ForEach(bucket.items, id: \.id) { d in
                            deliverableRow(d)
                        }
                    }
                }
            }
        }
        .navigationTitle(Self.df.string(from: session.meetingDate))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    generateWork()
                } label: {
                    Label("Generate Work", systemImage: "doc.badge.plus")
                }
            }
        }
        .sheet(item: $showLessonPickerForDeliverable) { target in
            BookClubLessonPickerSheet(
                viewModel: {
                    let initialIDs = Set([UUID(uuidString: target.studentID)].compactMap { $0 })
                    let vm = LessonPickerViewModel(selectedStudentIDs: initialIDs)
                    vm.configure(lessons: lessons, students: students)
                    return vm
                }()
            ) { chosenID in
                if let chosenID { target.linkedLessonID = chosenID.uuidString }
                _ = saveCoordinator.save(modelContext, reason: "Link deliverable to lesson")
            }
        }
    }

    @ViewBuilder
    private func deliverableRow(_ d: BookClubDeliverable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Title", text: Binding(get: { d.title }, set: { d.title = $0 }))
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Picker("Status", selection: Binding(get: { d.status }, set: { d.status = $0 })) {
                    ForEach(BookClubDeliverableStatus.allCases, id: \.self) { s in
                        Text(label(for: s)).tag(s)
                    }
                }
                .pickerStyle(.menu)
                DatePicker("Due", selection: Binding(get: { d.dueDate ?? Date() }, set: { d.dueDate = $0 }), displayedComponents: .date)
                    .labelsHidden()
            }
            TextField("Instructions", text: Binding(get: { d.instructions }, set: { d.instructions = $0 }), axis: .vertical)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                if let lid = d.linkedLessonID, let uuid = UUID(uuidString: lid), let l = lessonsByID[uuid] {
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
                    showLessonPickerForDeliverable = d
                } label: {
                    Label("Choose Lesson", systemImage: "book")
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func label(for s: BookClubDeliverableStatus) -> String {
        switch s {
        case .assigned: return "Assigned"
        case .inProgress: return "In Progress"
        case .readyForReview: return "Ready for Review"
        case .completed: return "Completed"
        }
    }

    private func generateWork() {
        var created = 0
        for d in session.deliverables {
            guard d.generatedWorkID == nil else { continue }
            guard let lid = d.linkedLessonID, !lid.isEmpty else { continue }
            let contract = WorkContract(studentID: d.studentID, lessonID: lid, presentationID: nil, status: .active)
            contract.sourceContextType = .bookClubSession
            contract.sourceContextID = session.id.uuidString
            modelContext.insert(contract)
            d.generatedWorkID = contract.id
            created += 1
        }
        if created > 0 {
            _ = saveCoordinator.save(modelContext, reason: "Generate work from book club session")
        }
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
