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
    @State private var resolvedPresentationID: UUID? = nil
    @State private var presentationNotes: [ScopedNote] = []
    @State private var showPresentationNotes: Bool = false

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
    
    private func resolvePresentationID() -> UUID? {
        // 1) Prefer explicit presentationID on the contract
        if let raw = contract.presentationID, let id = UUID(uuidString: raw) {
            return id
        }
        // 2) Fallback: map via legacyStudentLessonID
        if let legacy = contract.legacyStudentLessonID, !legacy.isEmpty {
            // Presentations expose legacyStudentLessonID as a String? that should match
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
                Text("Presentation Notes (Group)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(showPresentationNotes ? "Hide" : "Show") {
                    withAnimation(.easeInOut) { showPresentationNotes.toggle() }
                }
                .buttonStyle(.borderless)
            }
            if showPresentationNotes {
                if presentationNotes.isEmpty {
                    Text("No presentation notes")
                        .font(.subheadline)
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

            if workNotes.isEmpty {
                Text("No notes yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(workNotes, id: \.id) { note in
                        noteRow(note)
                    }
                }
            }

            if resolvedPresentationID != nil {
                presentationNotesSection()
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func headerSection() -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lessonTitle())
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(studentName())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showCompletionSheet = true
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
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
                Spacer()
                Button("Cancel") { showCompletionSheet = false }
                Button("Done") {
                    contract.status = .complete
                    contract.completedAt = Date()
                    contract.scheduledDate = nil
                    contract.completionOutcome = completionOutcome
                    let trimmed = completionNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    contract.completionNote = trimmed.isEmpty ? nil : trimmed
                    try? modelContext.save()
                    showCompletionSheet = false
                    close()
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
                    // Header
                    headerSection()

                    Picker("Status", selection: $status) {
                        ForEach(WorkStatus.allCases, id: \.self) { s in
                            Text(label(for: s)).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Work Kind picker (aligned under Status)
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Kind", selection: kindBinding) {
                            Text("Practice").tag(WorkKind.practiceLesson as WorkKind?)
                            Text("Follow-up").tag(WorkKind.followUpAssignment as WorkKind?)
                            Text("Research").tag(WorkKind.research as WorkKind?)
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().padding(.vertical, 4)

                    // Scheduling section
                    calendarSection()

                    Divider().padding(.top, 4)

                    // Schedule Next Lesson action
                    Button {
                        showScheduleSheet = true
                    } label: {
                        Label("Schedule Next Lesson…", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    
                    Divider().padding(.top, 8)

                    // Notes Section
                    notesSection()

                    HStack {
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
        .frame(minWidth: 360)
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleNextLessonSheet(contract: contract) {
                // On created: show a brief confirmation
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

    private func labelForScheduledReason(_ r: ScheduledReason) -> String {
        switch r {
        case .progressCheck: return "Progress Check"
        case .dueDate: return "Due Date"
        case .conference: return "Conference"
        case .reminder: return "Reminder"
        case .other: return "Other"
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

    // Map the sheet's ScheduledReason (contract-level) to WorkPlanItem.Reason (calendar item)
    private func mapReason(_ r: ScheduledReason?) -> WorkPlanItem.Reason? {
        guard let r else { return nil }
        switch r {
        case .progressCheck: return WorkPlanItem.Reason.progressCheck
        case .dueDate: return WorkPlanItem.Reason.dueDate
        case .conference: return WorkPlanItem.Reason.other // no direct equivalent in WorkPlanItem.Reason
        case .reminder: return WorkPlanItem.Reason.other   // no direct equivalent in WorkPlanItem.Reason
        case .other: return WorkPlanItem.Reason.other
        }
    }

    private func close() {
        if let onDone { onDone() } else { dismiss() }
    }

    private func save() {
        contract.status = status

        // Keep WorkPlanItem (calendar) as source of truth for scheduling
        let sd = scheduleDates
        let earliest = sd.primaryDate

        contract.scheduledDate = earliest

        if status == .complete {
            contract.completedAt = Date()
        } else {
            contract.completedAt = nil
        }

        // Persist new fields
        contract.kind = kind ?? contract.kind ?? ((contract.presentationID != nil) ? .practiceLesson : .followUpAssignment)

        try? modelContext.save()
        close()
    }
    
    private func addPlan() {
        let normalized = AppCalendar.startOfDay(newPlanDate)
        let note = newPlanNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = WorkPlanItem(workID: contract.id, scheduledDate: normalized, reason: newPlanReason, note: note.isEmpty ? nil : note)
        modelContext.insert(item)
        // Reset composer
        newPlanDate = Date()
        newPlanReason = .progressCheck
        newPlanNote = ""
    }

    private func deletePlanItem(_ item: WorkPlanItem) {
        modelContext.delete(item)
    }

    private func addNote(body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        let scope: ScopedNote.Scope
        if let sid = UUID(uuidString: contract.studentID) {
            scope = .student(sid)
        } else {
            scope = .all
        }
        let note = ScopedNote(
            createdAt: now,
            updatedAt: now,
            body: trimmed,
            scope: scope,
            legacyFingerprint: nil,
            migrationKey: nil,
            studentLesson: nil,
            work: nil,
            presentation: nil,
            workContract: contract
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
    static func resolveNextLessonID(from contract: WorkContract, lessons: [Lesson]) -> UUID? {
        guard let currentID = UUID(uuidString: contract.lessonID),
              let current = lessons.first(where: { $0.id == currentID }) else {
            return nil
        }

        // Attempt explicit link (not present in this model). Fallback to collection ordering.
        let currentSubject = current.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = current.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else {
            return nil
        }

        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }

        if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
            let next = candidates[idx + 1]
            return next.id
        } else {
            return nil
        }
    }
}

struct ScheduleNextLessonSheet: View {
    let contract: WorkContract
    var onCreated: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: \Lesson.name) private var lessons: [Lesson]
    @Query(sort: \Student.firstName) private var studentsAll: [Student]

    @State private var search: String = ""
    @State private var selectedLessonID: UUID? = nil
    @State private var showLessonPicker: Bool = true
    @State private var scheduleEnabled: Bool = false
    @State private var scheduleDate: Date = Date()
    @State private var notes: String = ""

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

    init(contract: WorkContract, onCreated: (() -> Void)? = nil) {
        self.contract = contract
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule Next Lesson")
                .font(.title2)
                .fontWeight(.semibold)

            // Auto-selected lesson (if any)
            if let selected = selectedLesson {
                HStack(alignment: .center, spacing: 12) {
                    LessonRow(lesson: selected,
                              subtitle: lessonSubtitle(selected),
                              isSelected: true)
                    Spacer()
                    Button("Change…") { withAnimation { showLessonPicker = true } }
                }
            } else {
                Text("Select a lesson")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Lesson picker
            if showLessonPicker || selectedLesson == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Lesson")
                        .font(.headline)
                    TextField("Search lessons…", text: $search)
                        .textFieldStyle(.roundedBorder)
                    List {
                        ForEach(filteredLessons) { lesson in
                            Button {
                                selectedLessonID = lesson.id
                                showLessonPicker = false
                            } label: {
                                LessonRow(lesson: lesson,
                                          subtitle: lessonSubtitle(lesson),
                                          isSelected: selectedLessonID == lesson.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(minHeight: 200)
                }
            }

            // Optional schedule + notes
            Toggle("Schedule on a date", isOn: $scheduleEnabled)
            if scheduleEnabled {
                DatePicker("Date", selection: $scheduleDate, displayedComponents: .date)
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedLessonID == nil)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 480)
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
        .onAppear { autoSelectNextLessonIfPossible() }
    }

    private func lessonSubtitle(_ lesson: Lesson) -> String? {
        let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [subject, group].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func autoSelectNextLessonIfPossible() {
        if let nextID = NextLessonResolver.resolveNextLessonID(from: contract, lessons: lessons) {
            selectedLessonID = nextID
            showLessonPicker = false
        } else {
            showLessonPicker = true
        }
    }

    private func create() {
        guard let lessonID = selectedLessonID else { return }
        guard let sid = UUID(uuidString: contract.studentID) else { return }

        // Prevent duplicates: same lesson + same single student + not given
        // Unscheduled de-dupes against unscheduled; scheduled de-dupes against the same scheduled day (startOfDay)
        if scheduleEnabled {
            let day = AppCalendar.startOfDay(scheduleDate)
            let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonID && $0.givenAt == nil && $0.scheduledFor == day })
            let existing = (try? modelContext.fetch(fetch)) ?? []
            if existing.contains(where: { Set($0.studentIDs) == Set([sid]) }) {
                dismiss()
                return
            }
        } else {
            let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonID && $0.givenAt == nil && $0.scheduledFor == nil })
            let existing = (try? modelContext.fetch(fetch)) ?? []
            if existing.contains(where: { Set($0.studentIDs) == Set([sid]) }) {
                dismiss()
                return
            }
        }

        let newSL = StudentLesson(
            id: UUID(),
            lessonID: lessonID,
            studentIDs: [sid],
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false,
            notes: notes,
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )

        // Set relationships
        let lessonFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
        let studentFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == sid })
        newSL.lesson = (try? modelContext.fetch(lessonFetch))?.first
        if let s = (try? modelContext.fetch(studentFetch))?.first { newSL.students = [s] }

        if scheduleEnabled {
            let normalized = AppCalendar.startOfDay(scheduleDate)
            newSL.setScheduledFor(normalized, using: AppCalendar.shared)
        }

        modelContext.insert(newSL)
        _ = saveCoordinator.save(modelContext, reason: "Schedule next lesson from WorkContract")
        onCreated?()
        dismiss()
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    let subtitle: String?
    let isSelected: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name)
                    .font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
    }
}

