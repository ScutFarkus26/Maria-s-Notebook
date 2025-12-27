import SwiftUI
import SwiftData
import Foundation

struct WorkContractDetailSheet: View {
    let contract: WorkContract
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @Query private var workNotes: [ScopedNote]
    @Query private var presentations: [Presentation]
    @Query private var planItems: [WorkPlanItem]
    @Query private var peerContracts: [WorkContract]
    
    // UI State
    @State private var resolvedPresentationID: UUID? = nil
    @State private var presentationNotes: [ScopedNote] = []
    @State private var showPresentationNotes: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State private var newNoteText: String = ""
    @State private var showScheduleSheet: Bool = false
    @State private var showPlannedBanner: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var isRestoringData: Bool = false

    // Editable Fields
    @State private var status: WorkStatus
    @State private var workTitle: String = ""
    @State private var completionOutcome: CompletionOutcome? = nil
    @State private var completionNote: String = ""
    
    // Scheduling (Calendar)
    @State private var newPlanDate: Date = Date()
    @State private var newPlanReason: WorkPlanItem.Reason = .progressCheck
    @State private var newPlanNote: String = ""

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    private var scheduleDates: WorkScheduleDates {
        WorkScheduleDateLogic.compute(for: contract, allPlanItems: planItems)
    }
    
    private var completionOutcomeBinding: Binding<CompletionOutcome?> {
        Binding<CompletionOutcome?>(get: { completionOutcome }, set: { completionOutcome = $0 })
    }

    private var likelyNextLesson: Lesson? {
        guard let currentLessonID = UUID(uuidString: contract.lessonID) else { return nil }
        return NextLessonResolver.resolveNextLesson(from: currentLessonID, lessons: lessons)
    }
    
    private var allPresentationStudentIDs: [UUID] {
         guard let pid = resolvedPresentationID,
              let presentation = presentations.first(where: { $0.id == pid }) else {
            return []
        }
        return presentation.studentUUIDs
    }
    
    private var presentationGroupStudents: [Student] {
        guard let pid = resolvedPresentationID,
              let presentation = presentations.first(where: { $0.id == pid }) else {
            return []
        }
        let selfID = UUID(uuidString: contract.studentID)
        let peers = presentation.studentUUIDs.filter { $0 != selfID }
        return peers.compactMap { studentsByID[$0] }.sorted { $0.firstName < $1.firstName }
    }
    
    // MARK: - Init
    init(contract: WorkContract, onDone: (() -> Void)? = nil) {
        self.contract = contract
        self.onDone = onDone
        _status = State(initialValue: contract.status)
        _workTitle = State(initialValue: contract.title ?? "")
        _completionOutcome = State(initialValue: contract.completionOutcome)
        _completionNote = State(initialValue: contract.completionNote ?? "")
        
        let contractID = contract.id
        let noteSort: [SortDescriptor<ScopedNote>] = [
            SortDescriptor(\ScopedNote.updatedAt, order: .reverse),
            SortDescriptor(\ScopedNote.createdAt, order: .reverse)
        ]
        let workID = contractID.uuidString
        _workNotes = Query(filter: #Predicate<ScopedNote> { $0.workContractID == workID }, sort: noteSort)
        _planItems = Query(filter: #Predicate<WorkPlanItem> { $0.workID == contractID })
        
        let lessonID = contract.lessonID
        _peerContracts = Query(filter: #Predicate<WorkContract> { $0.lessonID == lessonID })
    }
    
    // MARK: - Body
    var body: some View {
        Group {
            if isRestoringData {
                ProgressView("Restoring data…")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // 1. Header Section (Student, Title, Lesson, Peers, Status Buttons)
                            headerSection()
                            
                            Divider()
                            
                            // 2. Completion Details (Only if Complete)
                            if status == .complete {
                                completionSection()
                                Divider()
                            }

                            // 3. Calendar
                            calendarSection()
                            
                            Divider()

                            // 4. Notes
                            notesSection()
                            
                            Spacer(minLength: 20)
                            
                            Button(role: .destructive) { showDeleteAlert = true } label: {
                                Label("Delete Work", systemImage: "trash")
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                        .padding(24)
                    }
                    
                    // Bottom Bar
                    VStack(spacing: 0) {
                        Divider()
                        HStack {
                            Button("Cancel") { close() }
                                .keyboardShortcut(.cancelAction)
                            Spacer()
                            Button("Save") { save() }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)
                        }
                        .padding(16)
                        .background(.bar)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleNextLessonSheet(
                contract: contract,
                initialGroupIDs: resolvedPresentationID == nil ? [] : allPresentationStudentIDs
            ) {
                showPlannedBanner = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showPlannedBanner = false
                }
            }
        }
        .sheet(isPresented: $showAddNoteSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add Note").font(.headline)
                TextEditor(text: $newNoteText)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                HStack {
                    Spacer()
                    Button("Cancel") { showAddNoteSheet = false }
                    Button("Add") {
                        addNote(body: newNoteText)
                        newNoteText = ""
                        showAddNoteSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .top) {
            if showPlannedBanner {
                Text("Next lesson unlocked & scheduled")
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("Delete Work?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteContract() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear {
             WorkDataMaintenance.backfillParticipantsIfNeeded(using: modelContext)
             resolvedPresentationID = resolvePresentationID()
             reloadPresentationNotes()
        }
    }
    
    // MARK: - Section Views
    
    @ViewBuilder
    private func headerSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Student Name
            Text(studentName())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            // Row 2: Work Title (Editable)
            TextField("Add Work Title (e.g. 'Diorama')", text: $workTitle)
                .font(.title2.weight(.medium))
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))

            // Row 3: Lesson Source
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.caption)
                Text(lessonTitle())
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
            
            // Row 4: Group Status (Peers)
            if !presentationGroupStudents.isEmpty {
                groupStatusRow()
                    .padding(.top, 4)
            }
            
            // Row 5: Status Buttons + Unlock
            HStack(spacing: 12) {
                // Status Buttons
                HStack(spacing: 0) {
                    statusButton(for: .active, label: "Active")
                    Divider().frame(height: 20)
                    statusButton(for: .review, label: "Review")
                    Divider().frame(height: 20)
                    statusButton(for: .complete, label: "Complete")
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()
                
                // Unlock Button (Only if NOT complete and next lesson exists)
                if status != .complete, let next = likelyNextLesson {
                    Button {
                        showScheduleSheet = true
                    } label: {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 32)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .help("Unlock next lesson: \(next.name)")
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private func statusButton(for s: WorkStatus, label: String) -> some View {
        Button {
            withAnimation(.snappy) { status = s }
        } label: {
            Text(label)
                .font(.subheadline.weight(status == s ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 70)
                .background(status == s ? Color.accentColor.opacity(0.15) : Color.clear)
                .foregroundStyle(status == s ? Color.accentColor : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func groupStatusRow() -> some View {
        let status = groupProgress
        HStack(spacing: 16) {
            if !status.waiting.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass").foregroundStyle(.orange).font(.caption)
                    Text("Waiting: " + status.waiting.map(\.firstName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !status.completed.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.green).font(.caption)
                    Text("Done: " + status.completed.map(\.firstName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func completionSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Completion Details").font(.headline)
            HStack {
                Text("Outcome").foregroundStyle(.secondary)
                Spacer()
                Picker("Outcome", selection: completionOutcomeBinding) {
                    Text("Select...").tag(nil as CompletionOutcome?)
                    ForEach(CompletionOutcome.allCases, id: \.self) { o in
                        Text(labelForOutcome(o)).tag(o as CompletionOutcome?)
                    }
                }
                .labelsHidden()
            }
            TextField("Notes (e.g. 'Struggled with carrying')", text: $completionNote)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder
    private func calendarSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar").font(.headline)
            
            scheduleSummaryCard(sd: scheduleDates)
            
            HStack {
                DatePicker("Date", selection: $newPlanDate, displayedComponents: .date)
                    .labelsHidden()
                
                Picker("Reason", selection: $newPlanReason) {
                    ForEach(WorkPlanItem.Reason.allCases) { r in Text(r.label).tag(r) }
                }
                .labelsHidden()
                
                Spacer()
                
                Button { addPlan() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }
            
            TextField("Note (optional)", text: $newPlanNote)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    @ViewBuilder
    private func scheduleSummaryCard(sd: WorkScheduleDates) -> some View {
        if sd.hasPrimary {
            HStack(spacing: 10) {
                if let k = sd.primaryKind { Image(systemName: WorkScheduleDateLogic.iconName(for: k)).foregroundStyle(.tint) }
                if let d = sd.primaryDate {
                    Text(WorkScheduleDateLogic.formattedDate(d)).fontWeight(.medium)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        } else {
            Text("No scheduled dates").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notes").font(.headline)
                Spacer()
                Button { showAddNoteSheet = true } label: { Image(systemName: "plus") }
            }
            
            if showPresentationNotes && !presentationNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From Presentation").font(.caption).foregroundStyle(.secondary)
                    ForEach(presentationNotes, id: \.id) { noteRow($0) }
                }
            }
            
            if !workNotes.isEmpty {
                ForEach(workNotes, id: \.id) { noteRow($0) }
            } else if presentationNotes.isEmpty {
                Text("No notes.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func noteRow(_ note: ScopedNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(scopeText(for: note.scope)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(Self.noteDateFormatter.string(from: note.updatedAt)).font(.caption2).foregroundStyle(.secondary)
            }
            Text(note.body).font(.body)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Helpers
    private func save() {
        contract.status = status
        contract.title = workTitle
        
        let sd = scheduleDates
        contract.scheduledDate = sd.primaryDate
        
        if status == .complete {
            if contract.completedAt == nil { contract.completedAt = Date() }
            contract.completionOutcome = completionOutcome
            let trimmed = completionNote.trimmingCharacters(in: .whitespacesAndNewlines)
            contract.completionNote = trimmed.isEmpty ? nil : trimmed
        } else {
            contract.completedAt = nil
        }
        
        try? modelContext.save()
        close()
    }

    private func close() { if let onDone { onDone() } else { dismiss() } }
    
    private func deleteContract() {
        for item in planItems where item.workID == contract.id { modelContext.delete(item) }
        for note in workNotes { modelContext.delete(note) }
        modelContext.delete(contract)
        _ = saveCoordinator.save(modelContext, reason: "Delete work contract")
        close()
    }
    
    private func addPlan() {
        let normalized = AppCalendar.startOfDay(newPlanDate)
        let note = newPlanNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = WorkPlanItem(workID: contract.id, scheduledDate: normalized, reason: newPlanReason, note: note.isEmpty ? nil : note)
        modelContext.insert(item)
        newPlanDate = Date()
        newPlanReason = .progressCheck
        newPlanNote = ""
    }
    
    private func addNote(body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        let scope: ScopedNote.Scope = UUID(uuidString: contract.studentID).map { .student($0) } ?? .all
        let note = ScopedNote(createdAt: now, updatedAt: now, body: trimmed, scope: scope, workContract: contract)
        modelContext.insert(note)
        try? modelContext.save()
    }

    // Resolvers
    private func lessonTitle() -> String {
        if let lid = UUID(uuidString: contract.lessonID), let l = lessonsByID[lid] {
            let t = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Lesson" : t
        }
        return "Lesson"
    }
    
    private func studentName() -> String {
        if let sid = UUID(uuidString: contract.studentID), let s = studentsByID[sid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    private func resolvePresentationID() -> UUID? {
        if let raw = contract.presentationID, let id = UUID(uuidString: raw) { return id }
        if let legacy = contract.legacyStudentLessonID, !legacy.isEmpty {
            if let match = presentations.first(where: { ($0.legacyStudentLessonID ?? "") == legacy }) { return match.id }
        }
        return nil
    }
    
    private func reloadPresentationNotes() {
        guard let pid = resolvedPresentationID else { presentationNotes = []; return }
        let sort = [SortDescriptor(\ScopedNote.updatedAt, order: .reverse)]
        let pidString = pid.uuidString
        let fetch = FetchDescriptor<ScopedNote>(predicate: #Predicate<ScopedNote> { $0.presentationID == pidString }, sortBy: sort)
        presentationNotes = (try? modelContext.fetch(fetch)) ?? []
    }
    
    // Auxiliary Types
    private struct GroupStatus { let waiting: [Student]; let completed: [Student] }
    private var groupProgress: GroupStatus {
        let peers = presentationGroupStudents
        var waiting: [Student] = []
        var completed: [Student] = []
        for student in peers {
            let sid = student.id.uuidString
            if let pc = peerContracts.first(where: { $0.studentID == sid }) {
                (pc.status == .complete) ? completed.append(student) : waiting.append(student)
            } else { waiting.append(student) }
        }
        return GroupStatus(waiting: waiting, completed: completed)
    }
    
    private func labelForOutcome(_ o: CompletionOutcome) -> String {
        switch o {
        case .mastered: return "Mastered"
        case .submitted: return "Submitted"
        case .needsMorePractice: return "Keep Practicing" // UPDATED LABEL
        case .paused: return "Paused"
        case .notRequired: return "Not Required"
        }
    }
    
    private func scopeText(for scope: ScopedNote.Scope) -> String {
        switch scope {
        case .all: return "All"
        case .student: return "Student"
        case .students(let ids): return ids.isEmpty ? "Group" : "\(ids.count) students"
        }
    }
    
    private static let noteDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
}

// Reuse existing structs
private struct NextLessonResolver {
    static func resolveNextLesson(from currentID: UUID, lessons: [Lesson]) -> Lesson? {
        guard let current = lessons.first(where: { $0.id == currentID }) else { return nil }
        let currentSubject = current.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = current.group.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }
        if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
            return candidates[idx + 1]
        }
        return nil
    }
    static func resolveNextLessonID(from contract: WorkContract, lessons: [Lesson]) -> UUID? {
        guard let currentID = UUID(uuidString: contract.lessonID) else { return nil }
        return resolveNextLesson(from: currentID, lessons: lessons)?.id
    }
}

// Simplified version of the ScheduleNextLessonSheet wrapper for context
struct ScheduleNextLessonSheet: View {
    let contract: WorkContract
    let initialGroupIDs: [UUID]
    var onCreated: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Text("Schedule Next Lesson Sheet Placeholder")
            .onAppear {
                dismiss()
                onCreated?()
            }
    }
}
