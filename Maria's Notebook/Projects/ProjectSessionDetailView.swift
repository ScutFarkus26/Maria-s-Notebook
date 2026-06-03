import OSLog
import SwiftUI
import CoreData

struct ProjectSessionDetailView: View {
    private static let logger = Logger.projects
    let session: CDProjectSession

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames")
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true),
        NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)
    ]) private var studentsRaw: FetchedResults<CDStudent>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)])
    private var lessons: FetchedResults<CDLesson>

    // NEW: Query all work models to filter locally
    @FetchRequest(sortDescriptors: []) private var allWorkModels: FetchedResults<CDWorkModel>

    @State var showLessonPickerForWork: CDWorkModel?
    @State var showSelectionSheetForStudent: String?
    @State var showAddWorkSheet: Bool = false
    @State var stepEditorTarget: StepEditorTarget?
    @State private var sessionNotesText: String

    init(session: CDProjectSession) {
        self.session = session
        _sessionNotesText = State(initialValue: session.latestUnifiedNoteText)
    }

    var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filterEnrolled(),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    var studentsByID: [UUID: CDStudent] {
        Dictionary(
            students.compactMap { s in s.id.map { ($0, s) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
    var lessonsByID: [UUID: CDLesson] {
        Dictionary(
            Array(lessons).compactMap { l in l.id.map { ($0, l) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // Filter work models relevant to this session
    var sessionWorkModels: [CDWorkModel] {
        let sid = (session.id ?? UUID()).uuidString
        return allWorkModels.filter { work in
            let contextType = work.sourceContextType
            return (contextType == .projectSession || contextType == .bookClubSession) && work.sourceContextID == sid
        }
    }

    func studentName(for sid: String) -> String {
        studentsByID[uuidString: sid].map(StudentFormatter.displayName(for:)) ?? "Student"
    }

    /// Works grouped by student (for uniform mode or assigned works in choice mode)
    var groupedByStudent: [(id: String, items: [CDWorkModel])] {
        // For choice mode, only include works that have participants
        let items = session.assignmentMode == .choice
            ? sessionWorkModels.filter { !$0.isOffered }
            : sessionWorkModels

        var buckets: [String: [CDWorkModel]] = [:]
        var order: [String] = []

        for work in items {
            // For works with participants, sequence by each participant
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
    var offeredWorks: [CDWorkModel] {
        sessionWorkModels.filter(\.isOffered)
    }

    /// CDProject member IDs for showing selection status
    var projectMemberIDs: [String] {
        session.project?.memberStudentIDsArray ?? []
    }

    private var studentSelectionBinding: Binding<StudentIDWrapper?> {
        Binding<StudentIDWrapper?>(
            get: { showSelectionSheetForStudent.map { StudentIDWrapper(id: $0) } },
            set: { showSelectionSheetForStudent = $0?.id }
        )
    }

    private var lessonPickerBinding: Binding<WorkIDWrapper?> {
        Binding<WorkIDWrapper?>(
            get: { showLessonPickerForWork.flatMap { w in w.id.map { WorkIDWrapper(id: $0) } } },
            set: { wrapper in showLessonPickerForWork = wrapper.flatMap { w in allWorkModels.first { $0.id == w.id } } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionGroupBox
            sessionList
        }
        .navigationTitle(DateFormatters.mediumDate.string(from: session.meetingDate ?? Date()))
        .sheet(item: studentSelectionBinding) { wrapper in
            StudentSelectionSheet(
                session: session,
                studentID: wrapper.id,
                studentName: studentName(for: wrapper.id),
                offeredWorks: sessionWorkModels // All session works for selection
            )
        }
        .sheet(item: lessonPickerBinding) { wrapper in
            if let targetWork = allWorkModels.first(where: { $0.id == wrapper.id }) {
                ProjectLessonPickerSheet(
                    viewModel: {
                        let initialIDs = Set([UUID(uuidString: targetWork.studentID)].compactMap { $0 })
                        let vm = LessonPickerViewModel(selectedStudentIDs: initialIDs)
                        vm.configure(lessons: Array(lessons), students: students)
                        return vm
                    }()
                ) { chosenID in
                    if let chosenID {
                        targetWork.lessonID = chosenID.uuidString
                        targetWork.lastTouchedAt = Date()
                        saveProjectSession(reason: "Link Project Lesson")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddWorkSheet) {
            AddWorkOfferSheet(session: session)
        }
        .sheet(item: $stepEditorTarget) { target in
            WorkStepEditorSheet(work: target.work, existingStep: target.step) {
                saveProjectSession(reason: "Save Project Step")
            }
        }
    }

    private var sessionGroupBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Focus, lesson, or material", text: Binding(
                    get: { session.chapterOrPages ?? "" },
                    set: { session.chapterOrPages = $0.trimmed().isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Guide Observations")
                        .font(.headline)
                    TextField("Observation notes", text: $sessionNotesText, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveSessionNotes() }
                }

                agendaItemsEditor
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal)
        .onDisappear {
            saveSessionNotes()
            saveProjectSession(reason: "Save Project Check-In")
        }
    }

    private var agendaItemsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Student Questions & Next Steps")
                .font(.headline)
            ForEach(Array(session.agendaItems.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField("Question, observation, or next step", text: Binding(
                        get: {
                            session.agendaItems.indices.contains(index)
                                ? session.agendaItems[index] : ""
                        },
                        set: { newValue in
                            var items = session.agendaItems
                            if items.indices.contains(index) {
                                items[index] = newValue
                                session.agendaItems = items
                            }
                        }
                    ), axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        var items = session.agendaItems
                        if items.indices.contains(index) {
                            items.remove(at: index)
                            session.agendaItems = items
                            saveProjectSession(reason: "Remove Project Next Step")
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                var items = session.agendaItems
                items.append("")
                session.agendaItems = items
                saveProjectSession(reason: "Add Project Next Step")
            } label: {
                Label("Add Next Step", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private var sessionList: some View {
        List {
            if session.assignmentMode == .choice {
                Section {
                    HStack {
                        Label("Student Choice", systemImage: "hand.tap")
                        Spacer()
                        let totalCount: Int = offeredWorks.count + sessionWorkModels.filter { !$0.isOffered }.count
                        Text("Pick \(session.minSelections) of \(totalCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if session.assignmentMode == .choice {
                choiceModeContent
            } else {
                uniformModeContent
            }
        }
    }

    func editStep(for work: CDWorkModel, step: CDWorkStep?) {
        stepEditorTarget = StepEditorTarget(work: work, step: step)
    }

    func saveProjectSession(reason: String) {
        session.project?.modifiedAt = Date()
        saveCoordinator.save(modelContext, reason: reason)
    }

    private func saveSessionNotes() {
        let trimmed = sessionNotesText.trimmed()
        if trimmed != session.latestUnifiedNoteText.trimmed() {
            session.setLegacyNoteText(trimmed.isEmpty ? nil : trimmed, in: modelContext)
        }
    }

    struct StepEditorTarget: Identifiable {
        let id: String
        let work: CDWorkModel
        let step: CDWorkStep?

        init(work: CDWorkModel, step: CDWorkStep?) {
            self.work = work
            self.step = step
            let workID = work.objectID.uriRepresentation().absoluteString
            let stepID = step?.objectID.uriRepresentation().absoluteString ?? "new"
            self.id = "\(workID)-\(stepID)"
        }
    }

    private struct WorkIDWrapper: Identifiable {
        let id: UUID
    }

    private struct StudentIDWrapper: Identifiable {
        let id: String
    }
}
