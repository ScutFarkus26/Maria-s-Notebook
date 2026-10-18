import OSLog
import SwiftUI
import CoreData

struct ProjectSessionDetailView: View {
    let session: CDProjectSession

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dependencies) private var dependencies

    // Test student filtering
    @TestStudentVisibility private var testStudents

    // NEW: Query all work models to filter locally
    @FetchRequest(sortDescriptors: []) private var allWorkModels: FetchedResults<CDWorkModel>

    @State var showLessonPickerForWork: CDWorkModel?
    @State var showSelectionSheetForStudent: String?
    @State var showAddWorkSheet: Bool = false
    @State var stepEditorTarget: StepEditorTarget?
    @State private var sessionNotesText: String
    /// The field note as this page loaded or last wrote it.
    @State private var sessionNotesBase: String
    /// A typed edit's save, waiting for the typing to pause.
    @State private var pendingSave: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    init(session: CDProjectSession) {
        self.session = session
        // The field note `saveSessionNotes` saves back, not the newest observation.
        sessionNotesText = session.legacyNoteText
        sessionNotesBase = session.legacyNoteText
    }

    var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            dependencies.roster.enrolled,
            show: testStudents.show,
            namesRaw: testStudents.namesRaw
        )
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    var studentsByID: [UUID: CDStudent] {
        Dictionary(
            students.compactMap { s in s.id.map { ($0, s) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
    var lessonsByID: [UUID: CDLesson] { dependencies.lessonCatalog.byID }

    // Filter work models relevant to this session
    var sessionWorkModels: [CDWorkModel] {
        let sid = (session.id ?? UUID()).uuidString
        return allWorkModels.filter { work in
            let contextType = work.sourceContextType
            return (contextType == .projectSession || contextType == .bookClubSession) && work.sourceContextID == sid
        }
    }

    func studentName(for sid: String) -> String {
        if let student = studentsByID[uuidString: sid] { return student.shortName }
        // A child who has left keeps her name on the work she did here.
        return dependencies.roster.all.first { $0.id?.uuidString == sid }?.shortName ?? "Student"
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

    /// The project's members still in the class (and shown), for selection
    /// status. The member list keeps every child ever added.
    var projectMemberIDs: [String] {
        let shown = studentsByID
        return (session.project?.memberStudentIDsArray ?? []).filter { shown[uuidString: $0] != nil }
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
                ProjectLessonPickerSheet(chosenLessonID: UUID(uuidString: targetWork.lessonID)) { chosenID in
                    targetWork.lessonID = chosenID.uuidString
                    targetWork.lastTouchedAt = Date()
                    saveProjectSession(reason: "Link Project Lesson")
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
                        .onSubmit { saveProjectSession(reason: "Save Project Observation") }
                }

                agendaItemsEditor
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal)
        .onDisappear { saveProjectSession(reason: "Save Project Check-In") }
        // These fields write to the session; save once typing pauses rather
        // than only on leaving the screen (2026-10-10 sweep and review; the
        // notes since 2026-10-11 #72, which were lost when the app went away).
        .onChange(of: session.chapterOrPages) { _, _ in scheduleProjectSave(reason: "Edit Project Focus") }
        .onChange(of: session.agendaItems) { _, _ in scheduleProjectSave(reason: "Edit Project Next Step") }
        .onChange(of: sessionNotesText) { _, _ in scheduleProjectSave(reason: "Edit Project Observation") }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushPendingProjectSave() }
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

    /// Writes the typed notes, then saves the check-in when anything on it
    /// changed, stamping its project active. Leaving the page with nothing
    /// changed saves nothing (2026-10-11 #66).
    func saveProjectSession(reason: String) {
        pendingSave?.cancel()
        pendingSave = nil
        saveSessionNotes()
        guard ProjectCheckInSave.prepareSave(session, works: sessionWorkModels) else { return }
        saveCoordinator.save(modelContext, reason: reason)
    }

    /// Saves after typing pauses for 0.8 s, so a word is one save and one
    /// CloudKit push rather than one per keystroke.
    func scheduleProjectSave(reason: String) {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            saveProjectSession(reason: reason)
        }
    }

    /// Saves a typed edit still waiting, the notes included, when leaving the app.
    func flushPendingProjectSave() {
        saveProjectSession(reason: "Save Project Check-In")
    }

    /// Writes the notes field into the session when she changed it, never
    /// her old text over a newer note from another device (2026-10-11 #73).
    private func saveSessionNotes() {
        guard let text = ProjectCheckInSave.noteToWrite(
            typed: sessionNotesText, base: sessionNotesBase, stored: session.legacyNoteText
        ) else { return }
        session.setLegacyNoteText(text.isEmpty ? nil : text, in: modelContext)
        sessionNotesBase = text
        // A merge with the newer note: show what was saved.
        if text != sessionNotesText.trimmed() { sessionNotesText = text }
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
