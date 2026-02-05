import SwiftUI
import SwiftData
import UniformTypeIdentifiers
// Uses WorkScheduleDateLogic for consistent labeling

struct WorkAgendaCalendarPane: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    let startDate: Date
    let daysCount: Int

    // Sheet for choosing reason and note when dropping
    @State private var prompt: PlanPrompt? = nil

    private struct SelectionToken: Identifiable, Equatable { let id: UUID; let contractID: UUID }
    @State private var selected: SelectionToken? = nil

    struct PlanPrompt: Identifiable {
        let id = UUID()
        let workID: UUID
        let date: Date
        var reason: WorkPlanItem.Reason = .progressCheck
        var note: String = ""
    }

    var body: some View {
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
            if let token = selected {
                let id = token.contractID
                // Try to find WorkModel by id first (if already migrated)
                let workModelFetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
                if let workModel = modelContext.safeFetchFirst(workModelFetch) {
                    WorkDetailView(workID: workModel.id) {
                        selected = nil
                    }
                    .id(token.id)
                } else {
                    // Fallback: try to find WorkModel by legacyContractID (if not yet migrated)
                    let legacyFetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.legacyContractID == id })
                    if let workModel = modelContext.safeFetchFirst(legacyFetch) {
                        WorkDetailView(workID: workModel.id) {
                            selected = nil
                        }
                        .id(token.id)
                    } else {
                        ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
    }

    private func computeDays() -> [Date] {
        SchoolDayChecker.nextSchoolDays(from: startDate, count: daysCount, using: modelContext)
    }

    @ViewBuilder
    private func dayColumn(_ day: Date, availableHeight: CGFloat) -> some View {
        WorkAgendaDayColumn(day: day, availableHeight: availableHeight) { item in
            if let workID = item.workID.asUUID {
                openDetail(workID: workID)
            }
        }
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
                    case .studentLesson(let id):
                        rescheduleStudentLesson(id: id, to: normalizedDay)
                    case .workPlanItem(let id):
                        reschedulePlanItem(id: id, to: normalizedDay)
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
                        reschedulePlanItem(id: id, to: normalizedDay)
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
    private func savePlan(workID: UUID, date: Date, reason: WorkPlanItem.Reason?, note: String) {
        let normalized = AppCalendar.startOfDay(date)
        let item = WorkPlanItem(workID: workID, scheduledDate: normalized, reason: reason, note: note.isEmpty ? nil : note)
        modelContext.insert(item)
        if let work = fetchWork(id: workID) {
            work.dueAt = normalized
        }
        _ = saveCoordinator.save(modelContext, reason: "Create WorkPlanItem")
    }

    private func reschedulePlanItem(id: UUID, to day: Date) {
        let fetch = FetchDescriptor<WorkPlanItem>(predicate: #Predicate<WorkPlanItem> { $0.id == id })
        guard let item = modelContext.safeFetchFirst(fetch),
              let workID = item.workID.asUUID else { return }

        let normalized = AppCalendar.startOfDay(day)
        item.scheduledDate = normalized
        if let work = fetchWork(id: workID) {
            work.dueAt = normalized
        }
        _ = saveCoordinator.save(modelContext, reason: "Reschedule WorkPlanItem")
    }
    
    private func rescheduleStudentLesson(id: UUID, to day: Date) {
        let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate<StudentLesson> { $0.id == id })
        guard let lesson = modelContext.safeFetchFirst(fetch) else { return }
        
        let normalized = AppCalendar.startOfDay(day)
        let baseDate = Calendar.current.date(byAdding: .hour, value: 9, to: normalized) ?? normalized
        lesson.setScheduledFor(baseDate, using: AppCalendar.shared)
        
        _ = saveCoordinator.save(modelContext, reason: "Reschedule StudentLesson from Work view")
    }

    private func deletePlan(_ item: WorkPlanItem) {
        modelContext.delete(item)
        _ = saveCoordinator.save(modelContext, reason: "Delete WorkPlanItem")
    }
}

private struct PlanPromptSheetView: View {
    let prompt: WorkAgendaCalendarPane.PlanPrompt
    let onCancel: () -> Void
    let onSave: (WorkPlanItem.Reason, String) -> Void
    @State private var reason: WorkPlanItem.Reason = .progressCheck
    @State private var note: String = ""
    init(prompt: WorkAgendaCalendarPane.PlanPrompt, onCancel: @escaping () -> Void, onSave: @escaping (WorkPlanItem.Reason, String) -> Void) {
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
                Picker("Reason", selection: $reason) {
                    ForEach(WorkPlanItem.Reason.allCases) { r in Text(r.label).tag(r) }
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

