import SwiftUI
import SwiftData
import Foundation
#if DEBUG
#endif

struct WorkContractDetailSheet: View {
    let contract: WorkContract
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    
    // OPTIMIZATION: Load only related lessons and students instead of all
    @State private var relatedLesson: Lesson? = nil
    @State private var relatedLessons: [Lesson] = [] // For NextLessonResolver - same subject/group
    @State private var relatedStudent: Student? = nil
    
    @Query private var workNotes: [ScopedNote] // Legacy notes
    @State private var contractNotes: [Note] = [] // New unified notes - fetched in memory to avoid predicate issues
    @Query private var presentations: [Presentation]
    @Query private var planItems: [WorkPlanItem]
    @Query private var peerWorkModels: [WorkModel]
    
    @State private var resolvedPresentationID: UUID? = nil
    @State private var presentationNotes: [ScopedNote] = []
    @State private var showPresentationNotes: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State private var noteBeingEdited: Note? = nil
    @State private var scopedNoteBeingEdited: ScopedNote? = nil
    @State private var showScheduleSheet: Bool = false
    @State private var showPlannedBanner: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var isRestoringData: Bool = false
    @State private var correspondingWorkModel: WorkModel? = nil
    @State private var isReadOnly: Bool = true // WorkContract is read-only for legacy data

    @State private var status: WorkStatus
    @State private var workKind: WorkKind
    @State private var workTitle: String = ""
    @State private var completionOutcome: CompletionOutcome? = nil
    @State private var completionNote: String = ""
    
    @State private var newPlanDate: Date = Date()
    @State private var newPlanReason: WorkPlanItem.Reason = .progressCheck
    @State private var newPlanNote: String = ""

    private var scheduleDates: WorkScheduleDates {
        WorkScheduleDateLogic.compute(for: contract, allPlanItems: planItems)
    }
    
    private var likelyNextLesson: Lesson? {
        guard let currentLessonID = UUID(uuidString: contract.lessonID),
              relatedLessons.first(where: { $0.id == currentLessonID }) != nil else { return nil }
        return NextLessonResolver.resolveNextLesson(from: currentLessonID, lessons: relatedLessons)
    }

    init(contract: WorkContract, onDone: (() -> Void)? = nil) {
        self.contract = contract
        self.onDone = onDone
        _status = State(initialValue: contract.status)
        _workTitle = State(initialValue: contract.title ?? "")
        _completionOutcome = State(initialValue: contract.completionOutcome)
        _completionNote = State(initialValue: contract.completionNote ?? "")
        _workKind = State(initialValue: contract.kind ?? .practiceLesson)
        
        let contractID = contract.id
        let workID = contractID.uuidString
        _workNotes = Query(filter: #Predicate<ScopedNote> { $0.workContractID == workID })
        // Query for new unified notes attached to this contract - fetch all and filter in memory to avoid predicate issues with optional WorkContract
        // CloudKit compatibility: workID is now String, so use workID string
        _planItems = Query(filter: #Predicate<WorkPlanItem> { $0.workID == workID })
        let lessonID = contract.lessonID
        _peerWorkModels = Query(filter: #Predicate<WorkModel> { $0.lessonID == lessonID })
        
        #if DEBUG
        // Debug logging: Check if WorkContract fetches still return results
        Task { @MainActor in
            let contractsFetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.lessonID == lessonID })
            if let contracts = try? modelContext.fetch(contractsFetch), contracts.count > 0 {
                print("WARNING: WorkContract read-path still active in WorkContractDetailSheet.peerContracts init count=\(contracts.count)")
            }
        }
        #endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection()
                    Divider()
                    if status == .complete { completionSection(); Divider() }
                    calendarSection()
                    Divider()
                    notesSection()
                    
                    // WorkContract is read-only - disable delete for legacy data
                    if !isReadOnly {
                        Button(role: .destructive) { showDeleteAlert = true } label: {
                            Label("Delete Work", systemImage: "trash")
                        }.frame(maxWidth: .infinity).padding(.top, 20)
                    } else {
                        // Show read-only indicator
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("This is legacy data. Edit via WorkModel instead.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Button("Cancel") { close() }
                Spacer()
                if !isReadOnly {
                    Button("Save") { save() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Close") { close() }.buttonStyle(.borderedProminent)
                }
            }.padding(16).background(.bar)
        }
        .onAppear {
            loadRelatedData()
            checkForWorkModelMapping()
            loadContractNotes()
            #if DEBUG
            PerformanceLogger.logScreenLoad(
                screenName: "WorkContractDetailSheet",
                itemCounts: [
                    "lessons": relatedLessons.count,
                    "students": relatedStudent != nil ? 1 : 0,
                    "workNotes": workNotes.count,
                    "presentations": presentations.count,
                    "planItems": planItems.count,
                    "peerWorkModels": peerWorkModels.count,
                    "hasWorkModelMapping": correspondingWorkModel != nil ? 1 : 0
                ]
            )
            #endif
            resolvedPresentationID = resolvePresentationID()
            reloadPresentationNotes()
        }
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleNextLessonSheet(contract: contract) { showPlannedBanner = true }
        }
        .sheet(isPresented: $showAddNoteSheet) {
            UnifiedNoteEditor(
                context: noteContextForNewNote(),
                initialNote: nil,
                onSave: { _ in
                    // Note is automatically saved via relationship
                    showAddNoteSheet = false
                },
                onCancel: {
                    showAddNoteSheet = false
                }
            )
        }
        .sheet(item: $noteBeingEdited) { note in
            UnifiedNoteEditor(
                context: noteContext(for: note),
                initialNote: note,
                onSave: { _ in
                    noteBeingEdited = nil
                },
                onCancel: {
                    noteBeingEdited = nil
                }
            )
        }
        .sheet(item: $scopedNoteBeingEdited) { scopedNote in
            LegacyNoteEditor(
                title: "Edit Note",
                text: scopedNote.body,
                onSave: { newText in
                    scopedNote.body = newText
                    try? modelContext.save()
                    scopedNoteBeingEdited = nil
                },
                onCancel: {
                    scopedNoteBeingEdited = nil
                }
            )
        }
        .alert("Delete?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteContract() }
        }
    }

    @ViewBuilder
    private func headerSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(studentName()).font(.system(size: 34, weight: .bold, design: .rounded))
            TextField("Work Title", text: $workTitle)
                .font(.title2)
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                .disabled(isReadOnly)
            
            HStack {
                Label(lessonTitle(), systemImage: "book.closed").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Picker("Kind", selection: $workKind) {
                    Text("Practice").tag(WorkKind.practiceLesson)
                    Text("Follow-Up").tag(WorkKind.followUpAssignment)
                    Text("Project").tag(WorkKind.research)
                }
                .labelsHidden()
                .controlSize(.small)
                .disabled(isReadOnly)
            }

            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    statusBtn(.active, "Active"); statusBtn(.review, "Review"); statusBtn(.complete, "Complete")
                }.background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                
                if status != .complete, likelyNextLesson != nil {
                    Button { showScheduleSheet = true } label: {
                        Image(systemName: "lock.open.fill").padding(8).background(Color.accentColor.opacity(0.1)).cornerRadius(8)
                    }
                }
            }
        }
    }

    @ViewBuilder private func statusBtn(_ s: WorkStatus, _ label: String) -> some View {
        Button(label) {
            if !isReadOnly {
                status = s
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(status == s ? Color.accentColor.opacity(0.1) : Color.clear)
        .foregroundStyle(status == s ? Color.accentColor : .primary)
        .disabled(isReadOnly)
    }

    @ViewBuilder private func completionSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Outcome", selection: $completionOutcome) {
                Text("Select...").tag(nil as CompletionOutcome?)
                ForEach(CompletionOutcome.allCases, id: \.self) { Text(labelForOutcome($0)).tag($0 as CompletionOutcome?) }
            }
            TextField("Notes", text: $completionNote).textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder private func calendarSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar").font(.headline)
            HStack {
                DatePicker("", selection: $newPlanDate, displayedComponents: .date).labelsHidden()
                Button("Add") { addPlan() }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Notes").font(.headline); Spacer(); Button("+") { showAddNoteSheet = true } }
            
            // Show new unified notes first
            ForEach(contractNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                noteRow(note)
            }
            
            // Show legacy ScopedNote objects for backward compatibility
            ForEach(workNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { scopedNote in
                scopedNoteRow(scopedNote)
            }
            
            if contractNotes.isEmpty && workNotes.isEmpty {
                Text("No notes yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
    
    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.body)
                .font(.body)
            HStack {
                if note.category != .general {
                    Text(note.category.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                Text(note.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .contextMenu {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }
    
    @ViewBuilder
    private func scopedNoteRow(_ scopedNote: ScopedNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scopedNote.body)
                .font(.body)
            Text(scopedNote.createdAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .contextMenu {
            Button {
                scopedNoteBeingEdited = scopedNote
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }

    private func save() {
        // WorkContract is read-only for legacy data - do not mutate
        // If a WorkModel exists, mutations should be done there instead
        guard !isReadOnly else {
            #if DEBUG
            print("⚠️ Attempted to save WorkContract \(contract.id) but it is read-only (legacy data)")
            #endif
            close()
            return
        }
        // This should not be reached in normal operation (WorkContract is read-only)
        contract.status = status
        contract.title = workTitle
        contract.kind = workKind
        contract.completionOutcome = completionOutcome
        contract.completionNote = completionNote
        saveCoordinator.save(modelContext, reason: "Saving work contract")
        close()
    }

    private func close() { onDone?() ?? dismiss() }
    
    private func deleteContract() {
        // WorkContract is read-only for legacy data - do not delete
        // If a WorkModel exists, deletion should be done there instead
        guard !isReadOnly else {
            #if DEBUG
            print("⚠️ Attempted to delete WorkContract \(contract.id) but it is read-only (legacy data)")
            #endif
            close()
            return
        }
        // This should not be reached in normal operation (WorkContract is read-only)
        modelContext.delete(contract)
        saveCoordinator.save(modelContext, reason: "Deleting work contract")
        close()
    }
    
    private func checkForWorkModelMapping() {
        // Check if there's a corresponding WorkModel using LegacyWorkAdapter
        let adapter = LegacyWorkAdapter(modelContext: modelContext)
        do {
            let allWorkModels = try adapter.fetchAllWorkModels()
            let workModelsByContractID = adapter.workModelsByLegacyContractID(workModels: allWorkModels)
            correspondingWorkModel = adapter.resolveWorkModel(forLegacyContract: contract, map: workModelsByContractID)
            // WorkContract is always read-only - if a WorkModel exists, that's the source of truth
            // If no WorkModel exists, WorkContract is still read-only (legacy data only)
            isReadOnly = true
        } catch {
            #if DEBUG
            print("⚠️ Failed to check WorkModel mapping for WorkContract \(contract.id): \(error)")
            #endif
            isReadOnly = true
        }
    }

    private func addPlan() {
        let item = WorkPlanItem(workID: contract.id, scheduledDate: newPlanDate, reason: newPlanReason)
        modelContext.insert(item)
        saveCoordinator.save(modelContext, reason: "Adding plan item")
    }

    /// OPTIMIZATION: Load only related lessons and students on demand
    private func loadRelatedData() {
        // Load the specific lesson
        if let lessonID = UUID(uuidString: contract.lessonID) {
            let lessonDescriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate<Lesson> { $0.id == lessonID }
            )
            relatedLesson = modelContext.safeFetchFirst(lessonDescriptor)
            
            // If we found the lesson, load lessons in the same subject/group for NextLessonResolver
            if let lesson = relatedLesson {
                let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !subject.isEmpty, !group.isEmpty else { return }
                
                // Load all lessons and filter in memory (predicates don't support trimmingCharacters or caseInsensitiveCompare)
                let allLessonsDescriptor = FetchDescriptor<Lesson>(
                    sortBy: [SortDescriptor(\.orderInGroup)]
                )
                let allLessons = modelContext.safeFetch(allLessonsDescriptor)
                relatedLessons = allLessons.filter { l in
                    let lSubject = l.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lGroup = l.group.trimmingCharacters(in: .whitespacesAndNewlines)
                    return lSubject.caseInsensitiveCompare(subject) == .orderedSame &&
                           lGroup.caseInsensitiveCompare(group) == .orderedSame
                }
            }
        }
        
        // Load the specific student
        if let studentID = UUID(uuidString: contract.studentID) {
            let studentDescriptor = FetchDescriptor<Student>(
                predicate: #Predicate<Student> { $0.id == studentID }
            )
            relatedStudent = modelContext.safeFetchFirst(studentDescriptor)
        }
    }
    
    private func studentName() -> String {
        return relatedStudent?.firstName ?? "Student"
    }

    private func lessonTitle() -> String {
        return relatedLesson?.name ?? "Lesson"
    }
    
    // Task requirement #4: Fix call site to use presentation when available instead of .general
    private func noteContextForNewNote() -> UnifiedNoteEditor.NoteContext {
        // Priority 1: Use presentation if available (Task requirement #4)
        if let presentationID = resolvedPresentationID,
           let presentation = presentations.first(where: { $0.id == presentationID }) {
            return .presentation(presentation)
        }
        // Priority 2: Use corresponding WorkModel if available
        if let workModel = correspondingWorkModel {
            return .work(workModel)
        }
        // Last resort: general (should be rare)
        return .general
    }
    
    private func noteContext(for note: Note) -> UnifiedNoteEditor.NoteContext {
        // Try to determine context from the note's relationships
        if let work = note.work {
            return .work(work)
        }
        if let studentLesson = note.studentLesson {
            return .studentLesson(studentLesson)
        }
        if let presentation = note.presentation {
            return .presentation(presentation)
        }
        // Fallback: Try to find presentation from contract if available
        if let presentationID = resolvedPresentationID,
           let presentation = presentations.first(where: { $0.id == presentationID }) {
            return .presentation(presentation)
        }
        // Fallback to corresponding WorkModel if available
        if let workModel = correspondingWorkModel {
            return .work(workModel)
        }
        return .general
    }

    private func resolvePresentationID() -> UUID? {
        guard let pid = contract.presentationID else { return nil }
        return UUID(uuidString: pid)
    }

    private func reloadPresentationNotes() { /* Logic for ScopedNotes */ }
    
    /// Load contract notes by fetching all notes and filtering in memory (avoid predicate issues with optional WorkContract)
    private func loadContractNotes() {
        let contractID = contract.id
        let allNotesDescriptor = FetchDescriptor<Note>()
        if let allNotes = try? modelContext.fetch(allNotesDescriptor) {
            contractNotes = allNotes.filter { $0.workContract?.id == contractID }
        }
    }

    private func labelForOutcome(_ o: CompletionOutcome) -> String {
        switch o {
        case .mastered: return "Mastered"
        case .needsMorePractice: return "Keep Practicing"
        default: return o.rawValue.capitalized
        }
    }
}

// MARK: - Helpers
private struct NextLessonResolver {
    static func resolveNextLesson(from currentID: UUID, lessons: [Lesson]) -> Lesson? {
        guard let current = lessons.first(where: { $0.id == currentID }) else { return nil }
        let candidates = lessons.filter { $0.subject == current.subject && $0.group == current.group }
            .sorted { $0.orderInGroup < $1.orderInGroup }
        if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
            return candidates[idx + 1]
        }
        return nil
    }
}

struct ScheduleNextLessonSheet: View {
    let contract: WorkContract
    var onCreated: () -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Button("Tap to Unlock") { onCreated(); dismiss() }.padding()
    }
}
