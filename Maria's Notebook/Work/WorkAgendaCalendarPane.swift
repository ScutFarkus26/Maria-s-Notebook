import OSLog
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
// Uses WorkScheduleDateLogic for consistent labeling

struct WorkAgendaCalendarPane: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    let startDate: Date
    let daysCount: Int

    // Sheet for choosing reason and note when dropping
    @State private var prompt: PlanPrompt?

    private struct SelectionToken: Identifiable, Equatable { let id: UUID; let contractID: UUID }
    @State private var selected: SelectionToken?
    @State private var selectedGroup: WorkAgendaDayColumn.CheckInGroup? = nil
    
    @AppStorage(UserDefaultsKeys.workCalendarShowPresentations) private var showPresentations: Bool = true

    struct PlanPrompt: Identifiable {
        let id = UUID()
        let workID: UUID
        let date: Date
        var reason: String = "progressCheck" // Phase 6: Changed from WorkPlanItem.Reason
        var note: String = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    showPresentations.toggle()
                } label: {
                    Image(systemName: showPresentations ? "checkmark.square" : "square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(showPresentations ? "Hide presentations" : "Show presentations")
            }
            .padding(.horizontal, UIConstants.contentHorizontalPadding)
            .padding(.vertical, AppTheme.Spacing.small)
            
            GeometryReader { proxy in
                let days = computeDays()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(days, id: \.self) { day in
                            dayColumn(day, availableHeight: proxy.size.height)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .frame(height: proxy.size.height, alignment: .top)
                }
            }
        }
        // Fix: Use 'isPresented' to avoid ambiguity between standard 'sheet(item:)' and 'SheetPresentationHelpers' extension
        .sheet(isPresented: Binding(
            get: { prompt != nil },
            set: { if !$0 { prompt = nil } }
        )) {
            if let p = prompt {
                PlanPromptSheetView(prompt: p, onCancel: { prompt = nil }, onSave: { reason, note in
                    savePlan(workID: p.workID, date: p.date, reason: reason, note: note)
                    prompt = nil
                })
            }
        }
        // Fix: Use 'isPresented' to avoid ambiguity between standard 'sheet(item:)' and 'SheetPresentationHelpers' extension
        .sheet(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        )) {
            if let token = selected,
               let workModel = modelContext.resolveWorkModel(from: token.contractID) {
                WorkDetailView(workID: workModel.id) {
                    selected = nil
                }
                .id(token.id)
            } else if selected != nil {
                ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedGroup != nil },
            set: { if !$0 { selectedGroup = nil } }
        )) {
            if let group = selectedGroup {
                GroupedCheckInDetailSheet(group: group, onSelectWork: { workID in
                    selectedGroup = nil
                    // Small delay so the group sheet can dismiss before the detail sheet opens
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        openDetail(workID: workID)
                    }
                })
            }
        }
    }

    private func computeDays() -> [Date] {
        SchoolDayChecker.nextSchoolDays(from: startDate, count: daysCount, using: modelContext)
    }

    @ViewBuilder
    private func dayColumn(_ day: Date, availableHeight: CGFloat) -> some View {
        WorkAgendaDayColumn(
            day: day,
            availableHeight: availableHeight,
            showPresentations: showPresentations,
            onPillTap: { item in
                if let workID = item.workID.asUUID {
                    openDetail(workID: workID)
                }
            },
            onGroupTap: { group in
                selectedGroup = group
            }
        )
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            handleDrop(providers: providers, onto: day)
        }
    }

    // MARK: - Data Fetching Helpers
    
    private func fetchWork(id: UUID) -> WorkModel? {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
        return modelContext.safeFetchFirst(descriptor)
    }
    
    // MARK: - Actions
    
    private func openDetail(workID: UUID) {
        selected = nil
        let token = SelectionToken(id: UUID(), contractID: workID)
        Task { @MainActor in
            selected = token
        }
    }

    // MARK: - Drop handling
    private func handleDrop(providers: [NSItemProvider], onto day: Date) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let s = (ns as String).trimmed()
            
            // Try parsing as UnifiedCalendarDragPayload first
            if let unifiedPayload = UnifiedCalendarDragPayload.parse(s) {
                Task { @MainActor in
                    let normalizedDay = AppCalendar.startOfDay(day)
                    switch unifiedPayload {
                    case .presentation(let id):
                        rescheduleLessonAssignment(id: id, to: normalizedDay)
                    case .workCheckIn(let id):
                        rescheduleCheckIn(id: id, to: normalizedDay)
                    // Phase 6: workPlanItem case removed - migrated to workCheckIn
                    }
                }
            }
            // Fallback to legacy WorkAgendaDragPayload for backwards compatibility
            else if let legacyPayload = WorkAgendaDragPayload.parse(s) {
                Task { @MainActor in
                    let normalizedDay = AppCalendar.startOfDay(day)
                    switch legacyPayload {
                    case .work(let id):
                        prompt = PlanPrompt(workID: id, date: normalizedDay)
                        updateWorkDueDate(workID: id, to: normalizedDay, reason: "Sync work dueDate on drop (prompt pending)")
                    case .checkIn(let id):
                        rescheduleCheckIn(id: id, to: normalizedDay)
                    }
                }
            }
        }
        return true
    }

    private func updateWorkDueDate(workID: UUID, to date: Date, reason: String) {
        if let work = fetchWork(id: workID) {
            work.dueAt = date
            _ = saveCoordinator.save(modelContext, reason: reason)
        }
    }

    // MARK: - Actions
    private func savePlan(workID: UUID, date: Date, reason: String?, note: String) {
        let normalized = AppCalendar.startOfDay(date)
        let noteOrNil = note.isEmpty ? nil : note
        
        // PHASE 6: Create WorkCheckIn only (WorkPlanItem removed)
        let checkIn = WorkCheckIn(
            workID: workID,
            date: normalized,
            status: .scheduled,
            purpose: reason ?? "progressCheck"
        )
        modelContext.insert(checkIn)
        if let noteText = noteOrNil, !noteText.trimmed().isEmpty {
            _ = checkIn.setLegacyNoteText(noteText, in: modelContext)
        }
        
        if let work = fetchWork(id: workID) {
            work.dueAt = normalized
        }
        _ = saveCoordinator.save(modelContext, reason: "Create WorkCheckIn")
    }

    private func rescheduleCheckIn(id: UUID, to day: Date) {
        let fetch = FetchDescriptor<WorkCheckIn>(predicate: #Predicate<WorkCheckIn> { $0.id == id })
        guard let checkIn = modelContext.safeFetchFirst(fetch),
              let workID = checkIn.workID.asUUID else { return }

        let normalized = AppCalendar.startOfDay(day)
        checkIn.date = normalized
        if let work = fetchWork(id: workID) {
            work.dueAt = normalized
        }
        _ = saveCoordinator.save(modelContext, reason: "Reschedule WorkCheckIn")
    }
    
    private func rescheduleLessonAssignment(id: UUID, to day: Date) {
        let fetch = FetchDescriptor<LessonAssignment>(predicate: #Predicate<LessonAssignment> { $0.id == id })
        guard let la = modelContext.safeFetchFirst(fetch) else { return }

        let normalized = AppCalendar.startOfDay(day)
        let baseDate = Calendar.current.date(byAdding: .hour, value: 9, to: normalized) ?? normalized
        la.scheduledFor = baseDate
        if la.state == .draft {
            la.stateRaw = LessonAssignmentState.scheduled.rawValue
        }
        la.modifiedAt = Date()

        _ = saveCoordinator.save(modelContext, reason: "Reschedule LessonAssignment from Work view")
    }


}

// MARK: - Grouped Check-In Detail Sheet

/// Shown when tapping a merged pill — lists all students sharing the same lesson/purpose check-in.
/// Styled like the Work Items column of the post-presentation workflow sheet.
struct GroupedCheckInDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let group: WorkAgendaDayColumn.CheckInGroup
    let onSelectWork: (UUID) -> Void

    private var purposeIcon: String {
        let p = group.purpose.lowercased()
        if p.contains("progress") || p.contains("check") { return "checkmark.circle" }
        else if p.contains("due") { return "calendar.badge.exclamationmark" }
        else if p.contains("assessment") { return "chart.bar" }
        else if p.contains("follow") { return "arrow.turn.down.right" }
        else { return "calendar" }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.lessonTitle)
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        if !group.purpose.isEmpty {
                            Label(group.purpose, systemImage: purposeIcon)
                                .foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                        }
                        Text(group.sortDate, style: .date)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)

                Divider()

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(zip(group.checkIns, group.studentNames)), id: \.0.id) { checkIn, studentName in
                            studentRow(checkIn: checkIn, studentName: studentName)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("\(group.checkIns.count) Students")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 340)
        .presentationSizingFitted()
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func studentRow(checkIn: WorkCheckIn, studentName: String) -> some View {
        let work: WorkModel? = checkIn.workID.asUUID.flatMap { id in
            modelContext.safeFetchFirst(FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id }))
        }
        return CheckInStudentRow(
            checkIn: checkIn,
            work: work,
            studentName: studentName,
            onOpen: {
                if let workID = checkIn.workID.asUUID { onSelectWork(workID) }
            }
        )
    }

}

// MARK: - Check-In Student Row

/// A single student row inside GroupedCheckInDetailSheet.
/// Owns its own note state so the text field is editable and saves back to the check-in.
private struct CheckInStudentRow: View {
    private static let logger = Logger.work

    @Environment(\.modelContext) private var modelContext

    let checkIn: WorkCheckIn
    let work: WorkModel?
    let studentName: String
    let onOpen: () -> Void

    @State private var noteText: String
    @State private var saveTask: Task<Void, Never>? = nil

    init(checkIn: WorkCheckIn, work: WorkModel?, studentName: String, onOpen: @escaping () -> Void) {
        self.checkIn = checkIn
        self.work = work
        self.studentName = studentName
        self.onOpen = onOpen
        _noteText = State(initialValue: checkIn.latestUnifiedNoteText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name row + status dots + open button
            HStack(spacing: 8) {
                Text(studentName)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                if let work {
                    statusDots(for: work)
                }
                Button(action: onOpen) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Inline note field
            TextField("Note about this student…", text: $noteText, axis: .vertical)
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .onChange(of: noteText) { _, newValue in
                    // Debounce saves so we don't write on every keystroke
                    saveTask?.cancel()
                    saveTask = Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        guard !Task.isCancelled else { return }
                        _ = checkIn.setLegacyNoteText(newValue, in: modelContext)
                        do {
                            try modelContext.save()
                        } catch {
                            Self.logger.warning("Failed to save note: \(error)")
                        }
                    }
                }
        }
        .padding(.horizontal, UIConstants.contentHorizontalPadding)
        .padding(.vertical, AppTheme.Spacing.compact)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous))
        .padding(.horizontal, UIConstants.dropZoneInnerPadding)
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }

    @ViewBuilder
    private func statusDots(for work: WorkModel) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(dotColor(for: work).opacity(i <= dotCount(for: work) ? 1.0 : 0.18))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func dotCount(for work: WorkModel) -> Int {
        switch work.status {
        case .active: return 2
        case .review: return 4
        case .complete: return 5
        }
    }

    private func dotColor(for work: WorkModel) -> Color {
        switch work.status {
        case .active: return .orange
        case .review: return .green
        case .complete: return .blue
        }
    }
}

private struct PlanPromptSheetView: View {
    let prompt: WorkAgendaCalendarPane.PlanPrompt
    let onCancel: () -> Void
    let onSave: (String, String) -> Void // Phase 6: Changed from WorkPlanItem.Reason to String
    @State private var reason: String = "progressCheck"
    @State private var note: String = ""
    init(prompt: WorkAgendaCalendarPane.PlanPrompt, onCancel: @escaping () -> Void, onSave: @escaping (String, String) -> Void) {
        self.prompt = prompt
        self.onCancel = onCancel
        self.onSave = onSave
        _reason = State(initialValue: prompt.reason)
        _note = State(initialValue: prompt.note)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schedule Work").font(.headline)
            Text(prompt.date, style: .date).font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                Picker("Purpose", selection: $reason) {
                    // Phase 6: Simple string-based purposes
                    Text("Progress Check").tag("progressCheck")
                    Text("Assessment").tag("assessment")
                    Text("Due Date").tag("dueDate")
                }
                .pickerStyle(.segmented)
            }
            TextField("Optional note", text: $note)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
            HStack { Spacer(); Button("Cancel", action: onCancel); Button("Save") { onSave(reason, note) }.keyboardShortcut(.defaultAction) }
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 520)
        .presentationSizingFitted()
        #endif
    }
}

