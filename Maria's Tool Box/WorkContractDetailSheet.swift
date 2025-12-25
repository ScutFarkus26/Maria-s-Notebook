import SwiftUI
import SwiftData
import Foundation

// Uses shared schedule logic

struct WorkContractDetailSheet: View {
    let contract: WorkContract
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @Query private var workNotes: [ScopedNote]
    @Query private var presentations: [Presentation]
    @Query private var planItems: [WorkPlanItem]
    
    // NEW: Fetch peer contracts to show waiting status
    @Query private var peerContracts: [WorkContract]
    
    @State private var resolvedPresentationID: UUID? = nil
    @State private var presentationNotes: [ScopedNote] = []
    @State private var showPresentationNotes: Bool = true

    // Notes UI state
    @State private var showAddNoteSheet: Bool = false
    @State private var newNoteText: String = ""

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    @State private var status: WorkStatus
    @State private var hasSchedule: Bool
    @State private var scheduledDate: Date
    @State private var showScheduleSheet: Bool = false
    @State private var showPlannedBanner: Bool = false

    @State private var kind: WorkKind? = nil
    @State private var scheduledReason: ScheduledReason? = nil
    @State private var scheduledNote: String = ""
    @State private var completionOutcome: CompletionOutcome? = nil
    @State private var completionNote: String = ""
    @State private var showCompletionSheet: Bool = false

    @State private var newPlanDate: Date = Date()
    @State private var newPlanReason: WorkPlanItem.Reason = .progressCheck
    @State private var newPlanNote: String = ""
    
    @State private var isRestoringData: Bool = false
    @State private var showDeleteAlert: Bool = false

    private var scheduleDates: WorkScheduleDates {
        WorkScheduleDateLogic.compute(for: contract, allPlanItems: planItems)
    }

    private var kindBinding: Binding<WorkKind?> {
        Binding<WorkKind?>(get: { kind ?? contract.kind }, set: { kind = $0 })
    }

    private var completionOutcomeBinding: Binding<CompletionOutcome?> {
        Binding<CompletionOutcome?>(get: { completionOutcome }, set: { completionOutcome = $0 })
    }

    init(contract: WorkContract, onDone: (() -> Void)? = nil) {
        self.contract = contract
        self.onDone = onDone
        _status = State(initialValue: contract.status)
        let d = contract.scheduledDate ?? Date()
        _hasSchedule = State(initialValue: contract.scheduledDate != nil)
        _scheduledDate = State(initialValue: d)
        
        _kind = State(initialValue: contract.kind)
        _scheduledReason = State(initialValue: contract.scheduledReason)
        _scheduledNote = State(initialValue: contract.scheduledNote ?? "")
        _completionOutcome = State(initialValue: contract.completionOutcome)
        _completionNote = State(initialValue: contract.completionNote ?? "")
        
        // Initialize note queries (newest first)
        let contractID = contract.id
        let noteSort: [SortDescriptor<ScopedNote>] = [
            SortDescriptor(\ScopedNote.updatedAt, order: .reverse),
            SortDescriptor(\ScopedNote.createdAt, order: .reverse)
        ]
        let workID = contractID.uuidString
        _workNotes = Query(filter: #Predicate<ScopedNote> { $0.workContractID == workID }, sort: noteSort)
        _planItems = Query(filter: #Predicate<WorkPlanItem> { $0.workID == contractID })
        
        // Initialize peer contracts query
        let lessonID = contract.lessonID
        _peerContracts = Query(filter: #Predicate<WorkContract> { $0.lessonID == lessonID })
    }
    
    private static let noteDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    private func scopeText(for scope: ScopedNote.Scope) -> String {
        switch scope {
        case .all: return "All"
        case .student(_): return "Student"
        case .students(let ids): return ids.isEmpty ? "Group" : "\(ids.count) students"
        }
    }

    private func lessonTitle() -> String {
        if let lid = UUID(uuidString: contract.lessonID), let l = lessonsByID[lid] {
            let t = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return "Lesson"
    }
    private func studentName() -> String {
        if let sid = UUID(uuidString: contract.studentID), let s = studentsByID[sid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }
    
    // MARK: - Group Logic
    private var presentationGroupStudents: [Student] {
        guard let pid = resolvedPresentationID,
              let presentation = presentations.first(where: { $0.id == pid }) else {
            return []
        }
        let selfID = UUID(uuidString: contract.studentID)
        let peers = presentation.studentUUIDs.filter { $0 != selfID }
        return peers.compactMap { studentsByID[$0] }.sorted { $0.firstName < $1.firstName }
    }
    
    private var allPresentationStudentIDs: [UUID] {
         guard let pid = resolvedPresentationID,
              let presentation = presentations.first(where: { $0.id == pid }) else {
            return []
        }
        return presentation.studentUUIDs
    }
    
    private struct GroupStatus {
        let waiting: [Student]
        let completed: [Student]
    }

    private var groupProgress: GroupStatus {
        let peers = presentationGroupStudents
        var waiting: [Student] = []
        var completed: [Student] = []

        for student in peers {
            let sid = student.id.uuidString
            // Find contract for this peer + this lesson
            if let peerContract = peerContracts.first(where: { $0.studentID == sid }) {
                if peerContract.status == .complete {
                    completed.append(student)
                } else {
                    waiting.append(student)
                }
            } else {
                // No contract means waiting (or hasn't started)
                waiting.append(student)
            }
        }
        return GroupStatus(waiting: waiting, completed: completed)
    }
    
    // MARK: - Next Lesson Logic
    private var likelyNextLesson: Lesson? {
        guard let currentLessonID = UUID(uuidString: contract.lessonID) else { return nil }
        return NextLessonResolver.resolveNextLesson(from: currentLessonID, lessons: lessons)
    }

    private func resolvePresentationID() -> UUID? {
        if let raw = contract.presentationID, let id = UUID(uuidString: raw) {
            return id
        }
        if let legacy = contract.legacyStudentLessonID, !legacy.isEmpty {
            if let match = presentations.first(where: { ($0.legacyStudentLessonID ?? "") == legacy }) {
                return match.id
            }
        }
        return nil
    }
    
    private func reloadPresentationNotes() {
        guard let pid = resolvedPresentationID else {
            presentationNotes = []
            return
        }
        let sort: [SortDescriptor<ScopedNote>] = [
            SortDescriptor(\ScopedNote.updatedAt, order: .reverse),
            SortDescriptor(\ScopedNote.createdAt, order: .reverse)
        ]
        let pidString = pid.uuidString
        let fetch = FetchDescriptor<ScopedNote>(
            predicate: #Predicate<ScopedNote> { $0.presentationID == pidString },
            sortBy: sort
        )
        presentationNotes = (try? modelContext.fetch(fetch)) ?? []
    }

    private var relevantPlanItemsForContract: [WorkPlanItem] {
        planItems.filter { $0.workID == contract.id }
    }

    private var lastTouchedDaysSince: Int {
        contract.daysSinceLastTouch(modelContext: modelContext, planItems: relevantPlanItemsForContract, notes: workNotes)
    }

    private var agingBucketValue: AgingBucket {
        contract.agingBucket(modelContext: modelContext, planItems: relevantPlanItemsForContract, notes: workNotes)
    }

    private var presentationIDsForChange: [UUID] { presentations.map { $0.id } }
    private var planChangeMarkers: [PlanItemMarker] { planItems.map { PlanItemMarker(id: $0.id, date: $0.scheduledDate) } }

    // MARK: - UI Components
    
    @ViewBuilder
    private func headerSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Student Name
            Text(studentName())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // 2. Lesson Source
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color.accentColor)
                Text(lessonTitle())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 4)
            
            // 3. Work Info
            VStack(alignment: .leading, spacing: 4) {
                Text(kind?.rawValue.capitalized ?? contract.kind?.rawValue.capitalized ?? "Work")
                     .font(.headline)
                     .foregroundStyle(.secondary)
                
                if let note = contract.scheduledNote, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // 4. Group Progress Status
            if !presentationGroupStudents.isEmpty {
                let status = groupProgress
                VStack(alignment: .leading, spacing: 8) {
                    // Waiting
                    if !status.waiting.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "hourglass")
                                .foregroundStyle(.orange)
                                .font(.caption)
                                .padding(.top, 3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Waiting for:")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                
                                Text(status.waiting.map(\.firstName).joined(separator: ", "))
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    
                    // Completed
                    if !status.completed.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green.opacity(0.8))
                                .font(.caption)
                                .padding(.top, 3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Completed:")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                
                                Text(status.completed.map(\.firstName).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if status.waiting.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text("Group ready for next lesson")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(status.waiting.isEmpty ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func scheduleSummaryCard(sd: WorkScheduleDates) -> some View {
        if sd.hasPrimary {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if let k = sd.primaryKind { Image(systemName: WorkScheduleDateLogic.iconName(for: k)).foregroundStyle(.tint) }
                    if let d = sd.primaryDate, let k = sd.primaryKind {
                        Text(WorkScheduleDateLogic.formattedDate(d))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(WorkScheduleDateLogic.label(for: k))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                    Spacer(minLength: 0)
                    Text(WorkScheduleDateLogic.primaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let secDate = sd.secondaryDate, let sk = sd.secondaryKind {
                    HStack(spacing: 8) {
                        Image(systemName: WorkScheduleDateLogic.iconName(for: sk))
                            .foregroundStyle(.secondary)
                        Text(WorkScheduleDateLogic.label(for: sk))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(WorkScheduleDateLogic.formattedDate(secDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
        } else if let fb = WorkScheduleDateLogic.nextAnyDate(forPlanItems: planItems) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(WorkScheduleDateLogic.formattedDate(fb.date))
                        .font(.headline.weight(.semibold))
                    Text(fb.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(WorkScheduleDateLogic.primaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
        } else {
            Text("No dates scheduled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func calendarSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calendar")
                .font(.headline)

            scheduleSummaryCard(sd: scheduleDates)

            if agingBucketValue != .fresh {
                Text("Last touched \(lastTouchedDaysSince)d ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            DatePicker("Date", selection: $newPlanDate, displayedComponents: .date)

            Picker("Why is this scheduled?", selection: $newPlanReason) {
                ForEach(WorkPlanItem.Reason.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.menu)

            TextField("Note (optional)", text: $newPlanNote)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button {
                    addPlan()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func presentationNotesSection() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Presentation Notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(showPresentationNotes ? "Hide" : "Show") {
                    withAnimation(.easeInOut) { showPresentationNotes.toggle() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if showPresentationNotes {
                if presentationNotes.isEmpty {
                    Text("No presentation notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(presentationNotes, id: \.id) { note in
                            noteRow(note)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                Text("Notes")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    showAddNoteSheet = true
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if resolvedPresentationID != nil {
                presentationNotesSection()
                    .padding(.bottom, 4)
            }

            if workNotes.isEmpty {
                Text("No additional notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(workNotes, id: \.id) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func completionSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mark Complete")
                .font(.headline)
            Picker("Outcome", selection: completionOutcomeBinding) {
                Text("—").tag(nil as CompletionOutcome?)
                ForEach(CompletionOutcome.allCases, id: \.self) { o in
                    Text(labelForOutcome(o)).tag(o as CompletionOutcome?)
                }
            }
            .pickerStyle(.menu)
            TextField("Completion note (optional)", text: $completionNote, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Cancel") { showCompletionSheet = false }
                Spacer()
                
                // Done & Next Workflow
                let next = likelyNextLesson
                Button(next != nil ? "Done & Next" : "Done") {
                    // 1. Mark Complete
                    performCompletion()
                    
                    // 2. Chain workflow
                    if next != nil {
                        showCompletionSheet = false
                        // Slight delay to allow sheet transition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showScheduleSheet = true
                        }
                    } else {
                        showCompletionSheet = false
                        close()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    var body: some View {
        Group {
            if isRestoringData {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Restoring data…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    // Revised Header
                    headerSection()

                    // Quick Actions Row
                    HStack(spacing: 12) {
                        Picker("Status", selection: $status) {
                            ForEach(WorkStatus.allCases, id: \.self) { s in
                                Text(label(for: s)).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        
                        Spacer()
                        
                        Button {
                            showCompletionSheet = true
                        } label: {
                            Label("Mark Complete", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }

                    Divider().padding(.vertical, 4)

                    // Scheduling section
                    calendarSection()

                    Divider().padding(.top, 4)

                    // Schedule Next Lesson action
                    let nextLessonName = likelyNextLesson?.name
                    Button {
                        showScheduleSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                            Text(nextLessonName != nil ? "Schedule: \(nextLessonName!)" : "Schedule Next Lesson…")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(status == .complete ? Color.orange : Color.accentColor)
                    
                    Divider().padding(.top, 8)

                    // Notes Section
                    notesSection()

                    HStack {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Spacer()

                        Button("Cancel") { close() }
                        Button("Save") { save() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 400)
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.medium, .large])
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
                Text("Add Note")
                    .font(.headline)
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
        .sheet(isPresented: $showCompletionSheet) {
            completionSheetContent()
        }
        .overlay(alignment: .top) {
            if showPlannedBanner {
                Text("Next lesson scheduled")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.green.opacity(0.95))
                    )
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                    .padding(.top, 8)
            }
        }
        .alert("Delete Work?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteContract()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear {
            WorkDataMaintenance.backfillParticipantsIfNeeded(using: modelContext)
            AppCalendar.adopt(timeZoneFrom: calendar)
            let newID = resolvePresentationID()
            resolvedPresentationID = newID
            reloadPresentationNotes()
            let sd = scheduleDates
            if let d = sd.primaryDate {
                hasSchedule = true
                scheduledDate = d
            } else {
                hasSchedule = false
            }
        }
        .onChange(of: presentationIDsForChange) { _, _ in
            let newID = resolvePresentationID()
            if newID != resolvedPresentationID {
                resolvedPresentationID = newID
                reloadPresentationNotes()
            }
        }
        .onChange(of: planChangeMarkers) { _, _ in
            let sd = scheduleDates
            if let d = sd.primaryDate {
                hasSchedule = true
                scheduledDate = d
            } else {
                hasSchedule = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AppDataWillBeReplaced)) { _ in
            isRestoringData = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .AppDataDidRestore)) { _ in
            isRestoringData = false
        }
    }

    @ViewBuilder
    private func noteRow(_ note: ScopedNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(scopeText(for: note.scope))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.12))
                    )
                Spacer()
                Text(Self.noteDateFormatter.string(from: note.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func label(for s: WorkStatus) -> String {
        switch s {
        case .active: return "Active"
        case .review: return "Review"
        case .complete: return "Complete"
        }
    }

    private func labelForOutcome(_ o: CompletionOutcome) -> String {
        switch o {
        case .mastered: return "Mastered"
        case .submitted: return "Submitted"
        case .needsMorePractice: return "Needs More Practice"
        case .paused: return "Paused"
        case .notRequired: return "Not Required"
        }
    }

    private func close() {
        if let onDone { onDone() } else { dismiss() }
    }
    
    private func performCompletion() {
        contract.status = .complete
        contract.completedAt = Date()
        contract.scheduledDate = nil
        contract.completionOutcome = completionOutcome
        let trimmed = completionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        contract.completionNote = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
    }

    private func save() {
        contract.status = status
        let sd = scheduleDates
        contract.scheduledDate = sd.primaryDate
        if status == .complete {
            contract.completedAt = Date()
        } else {
            contract.completedAt = nil
        }
        contract.kind = kind ?? contract.kind ?? ((contract.presentationID != nil) ? .practiceLesson : .followUpAssignment)
        try? modelContext.save()
        close()
    }
    
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
        let scope: ScopedNote.Scope
        if let sid = UUID(uuidString: contract.studentID) { scope = .student(sid) } else { scope = .all }
        let note = ScopedNote(
            createdAt: now, updatedAt: now, body: trimmed, scope: scope,
            legacyFingerprint: nil, migrationKey: nil, studentLesson: nil, work: nil, presentation: nil, workContract: contract
        )
        modelContext.insert(note)
        try? modelContext.save()
    }
}

private struct PlanItemMarker: Equatable {
    let id: UUID
    let date: Date?
}

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

struct ScheduleNextLessonSheet: View {
    let contract: WorkContract
    let initialGroupIDs: [UUID]
    var onCreated: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    //
    @StateObject private var actions = StudentLessonDetailActions()

    @Query(sort: \Lesson.name) private var lessons: [Lesson]
    @Query(sort: \Student.firstName) private var studentsAll: [Student]
    @Query private var studentLessonsAll: [StudentLesson]

    @State private var search: String = ""
    @State private var selectedLessonID: UUID? = nil
    @State private var showLessonPicker: Bool = true
    @State private var scheduleEnabled: Bool = false
    @State private var scheduleDate: Date = Date()
    @State private var notes: String = ""
    @State private var selectedStudentIDs: Set<UUID> = []

    private var selectedLesson: Lesson? {
        guard let id = selectedLessonID else { return nil }
        return lessons.first(where: { $0.id == id })
    }

    private var filteredLessons: [Lesson] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty { return lessons }
        return lessons.filter { l in
            let name = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = l.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = l.group.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.localizedCaseInsensitiveContains(term) || subject.localizedCaseInsensitiveContains(term) || group.localizedCaseInsensitiveContains(term)
        }
    }

    private var groupStudents: [Student] {
        studentsAll.filter { initialGroupIDs.contains($0.id) }
    }

    init(contract: WorkContract, initialGroupIDs: [UUID], onCreated: (() -> Void)? = nil) {
        self.contract = contract
        self.initialGroupIDs = initialGroupIDs
        self.onCreated = onCreated
        
        var ids = Set(initialGroupIDs)
        if let sid = UUID(uuidString: contract.studentID) {
            ids.insert(sid)
        }
        _selectedStudentIDs = State(initialValue: ids)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule Next Lesson")
                .font(.title2)
                .fontWeight(.semibold)

            if let selected = selectedLesson {
                HStack(alignment: .center, spacing: 12) {
                    LessonRow(lesson: selected, subtitle: lessonSubtitle(selected), isSelected: true)
                    Spacer()
                    Button("Change…") { withAnimation { showLessonPicker = true } }
                }
            } else {
                Text("Select a lesson").font(.headline).foregroundStyle(.secondary)
            }

            if showLessonPicker || selectedLesson == nil {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search lessons…", text: $search).textFieldStyle(.roundedBorder)
                    List {
                        ForEach(filteredLessons) { lesson in
                            Button {
                                selectedLessonID = lesson.id
                                showLessonPicker = false
                            } label: {
                                LessonRow(lesson: lesson, subtitle: lessonSubtitle(lesson), isSelected: selectedLessonID == lesson.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(minHeight: 150)
                }
            }
            Divider()
            
            if !groupStudents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Students").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(groupStudents) { student in
                                Button {
                                    if selectedStudentIDs.contains(student.id) { selectedStudentIDs.remove(student.id) } else { selectedStudentIDs.insert(student.id) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: selectedStudentIDs.contains(student.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedStudentIDs.contains(student.id) ? .blue : .secondary)
                                        Text(student.firstName)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.05)).cornerRadius(8)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Text("\(selectedStudentIDs.count) students selected").font(.caption).foregroundStyle(.secondary)
                }
            }

            Toggle("Schedule on a date", isOn: $scheduleEnabled)
            if scheduleEnabled { DatePicker("Date", selection: $scheduleDate, displayedComponents: .date) }
            TextField("Notes (optional)", text: $notes, axis: .vertical).textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedLessonID == nil || selectedStudentIDs.isEmpty)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 480).presentationSizing(.fitted)
    #else
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    #endif
        .onAppear { autoSelectNextLessonIfPossible() }
    }

    private func lessonSubtitle(_ lesson: Lesson) -> String? {
        let parts = [lesson.subject, lesson.group].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func autoSelectNextLessonIfPossible() {
        if let nextID = NextLessonResolver.resolveNextLessonID(from: contract, lessons: lessons) {
            selectedLessonID = nextID
            showLessonPicker = false
        } else { showLessonPicker = true }
    }

    private func create() {
        guard let lessonID = selectedLessonID else { return }
        guard let lesson = lessons.first(where: { $0.id == lessonID }) else { return }
        
        let success = actions.planNextLessonInGroup(
            next: lesson,
            selectedStudentIDs: selectedStudentIDs,
            studentsAll: studentsAll,
            lessons: lessons,
            studentLessonsAll: studentLessonsAll,
            context: modelContext
        )
        
        if success {
            if scheduleEnabled {
                // If the user picked a date, we need to update the newly created item
                // 'actions' creates it with nil schedule. We find it and update it.
                // Since actions uses modelContext.insert, we can find it in the context.
                let targetSet = selectedStudentIDs
                let day = AppCalendar.startOfDay(scheduleDate)
                
                // Find the fresh item
                let candidates = studentLessonsAll.filter {
                    $0.lessonID == lessonID &&
                    Set($0.studentIDs) == targetSet &&
                    $0.scheduledFor == nil
                }
                
                if let created = candidates.sorted(by: { $0.createdAt > $1.createdAt }).first {
                    created.setScheduledFor(day, using: AppCalendar.shared)
                    created.notes = notes
                    try? modelContext.save()
                }
            }
            onCreated?()
            dismiss()
        } else {
            // Failed (likely duplicate existed), just dismiss
            dismiss()
        }
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    let subtitle: String?
    let isSelected: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name).font(.body.weight(.medium))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
        }
    }
}
