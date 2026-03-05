import OSLog
import SwiftUI
import SwiftData

struct ProjectSessionDetailView: View {
    private static let logger = Logger.projects
    let session: ProjectSession

    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames")
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)])
    private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(
            studentsRaw.uniqueByID,
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }
    @Query(sort: [SortDescriptor(\Lesson.name)]) private var lessons: [Lesson]

    // NEW: Query all work models to filter locally
    @Query private var allWorkModels: [WorkModel]

    @State var showLessonPickerForWork: WorkModel?
    @State var showSelectionSheetForStudent: String?
    @State var showAddWorkSheet: Bool = false

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    var studentsByID: [UUID: Student] {
        Dictionary(
            students.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
    var lessonsByID: [UUID: Lesson] {
        Dictionary(
            lessons.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // Filter work models relevant to this session
    var sessionWorkModels: [WorkModel] {
        let sid = session.id.uuidString
        return allWorkModels.filter { work in
            let contextType = work.sourceContextType
            return (contextType == .projectSession || contextType == .bookClubSession) && work.sourceContextID == sid
        }
    }

    func studentName(for sid: String) -> String {
        if let uuid = UUID(uuidString: sid), let s = studentsByID[uuid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    /// Works grouped by student (for uniform mode or assigned works in choice mode)
    var groupedByStudent: [(id: String, items: [WorkModel])] {
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
    var offeredWorks: [WorkModel] {
        sessionWorkModels.filter { $0.isOffered }
    }

    /// Project member IDs for showing selection status
    var projectMemberIDs: [String] {
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
                        ForEach(Array(session.agendaItems.enumerated()), id: \.offset) { index, _ in
                            HStack {
                                TextField("Agenda item", text: Binding(
                                    get: {
                                        session.agendaItems.indices.contains(index)
                                            ? session.agendaItems[index] : ""
                                    },
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
                                        do {
                                            try modelContext.save()
                                        } catch {
                                            Self.logger.warning("Failed to save after removing agenda item: \(error)")
                                        }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(AppColors.destructive)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button {
                            session.agendaItems.append("")
                            do {
                                try modelContext.save()
                            } catch {
                                print("⚠️ [\(#function)] Failed to save after adding agenda item: \(error)")
                            }
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
                do {
                    try modelContext.save()
                } catch {
                    ProjectSessionDetailView.logger.warning("Failed to save session on disappear: \(error)")
                }
            }

            List {
                // Assignment mode indicator
                if session.assignmentMode == .choice {
                    Section {
                        HStack {
                            Label("Student Choice", systemImage: "hand.tap")
                            Spacer()
                            let totalCount = offeredWorks.count + sessionWorkModels.filter { !$0.isOffered }.count
                            Text("Pick \(session.minSelections) of \(totalCount)")
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
            set: { wrapper in showLessonPickerForWork = wrapper.flatMap { w in allWorkModels.first { $0.id == w.id } } }
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
                    if chosenID != nil {
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

    static let df: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .medium; return df
    }()
}
