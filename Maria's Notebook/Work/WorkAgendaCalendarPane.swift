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
        .sheet(item: $prompt) { p in
            PlanPromptSheetView(prompt: p) { prompt = nil } onSave: { reason, note in
                savePlan(workID: p.workID, date: p.date, reason: reason, note: note)
                prompt = nil
            }
        }
        .sheet(item: $selected, onDismiss: { selected = nil }) { token in
            let id = token.contractID
            let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
            if let c = try? modelContext.fetch(fetch).first {
                WorkContractDetailSheet(contract: c) { selected = nil }
                    .id(token.id)
            } else {
                ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func computeDays() -> [Date] {
        var arr: [Date] = []
        var cursor = AppCalendar.startOfDay(startDate)
        var safety = 0
        while arr.count < daysCount && safety < 1000 {
            if !SchoolCalendar.isNonSchoolDay(cursor, using: modelContext) {
                arr.append(cursor)
            }
            cursor = AppCalendar.addingDays(1, to: cursor)
            safety += 1
        }
        return arr
    }

    @ViewBuilder
    private func dayColumn(_ day: Date, availableHeight: CGFloat) -> some View {
        let (start, end) = AppCalendar.dayRange(for: day)
        let descriptor = FetchDescriptor<WorkPlanItem>(predicate: #Predicate { $0.scheduledDate >= start && $0.scheduledDate < end })
        let items = (try? modelContext.fetch(descriptor)) ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(Date.FormatStyle().weekday(.abbreviated).day()))
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.id) { item in
                    pill(item)
                        .draggable(WorkAgendaDragPayload.checkIn(item.id).stringRepresentation) {
                            pill(item).opacity(0.9)
                        }
                }
            }
            .padding(8)
            .frame(minWidth: 260, idealWidth: 260, maxWidth: 260, minHeight: 0, idealHeight: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                handleDrop(providers: providers, onto: day)
            }
        }
        .frame(height: availableHeight, alignment: .topLeading)
    }

    // MARK: - Formatting helpers
    private func workTitle(for id: UUID) -> String {
        // Try to resolve from WorkContract, then Lesson name; fall back to a short lesson id or generic label.
        let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
        if let c = try? modelContext.fetch(fetch).first {
            if let lid = c.lessonID.asUUID {
                let lFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lid })
                if let l = try? modelContext.fetch(lFetch).first {
                    let name = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { return name }
                }
            }
            let short = String(c.lessonID.prefix(6))
            return "Lesson \(short)"
        }
        return "Work"
    }

    private func studentName(for id: UUID) -> String {
        let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
        if let c = try? modelContext.fetch(fetch).first, let sid = c.studentID.asUUID {
            let sFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == sid })
            if let s = try? modelContext.fetch(sFetch).first {
                return StudentFormatter.displayName(for: s)
            }
        }
        return ""
    }

    private func reasonLabel(_ reason: WorkPlanItem.Reason) -> String {
        switch reason {
        case .progressCheck:
            return WorkScheduleDateLogic.label(for: .checkIn)
        case .dueDate:
            return WorkScheduleDateLogic.label(for: .due)
        default:
            return reason.label
        }
    }

    @ViewBuilder
    private func pill(_ item: WorkPlanItem) -> some View {
        if let workID = item.workID.asUUID {
            let title = workTitle(for: workID)
            let name = studentName(for: workID)
            let reasonText = item.reason.map { reasonLabel($0) } ?? nil
            VStack(alignment: .leading, spacing: 4) {
            // Top row: Name first, then lesson title
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(name)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            // Second row: kind/reason (e.g., Check-In, Due)
            if let rt = reasonText {
                HStack(spacing: 6) {
                    if let r = item.reason { Image(systemName: r.icon).foregroundStyle(.secondary) }
                    Text(rt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if let workID = item.workID.asUUID {
                openDetail(workID: workID)
            }
        }
        .contextMenu {
            if let workID = item.workID.asUUID {
                Button("Open", systemImage: "arrow.forward.circle") { openDetail(workID: workID) }
            }
            Button("Delete", role: .destructive) { deletePlan(item) }
        }
        } else {
            Text("Invalid work ID").foregroundStyle(.red)
        }
    }

    private func openDetail(workID: UUID) {
        selected = nil
        let token = SelectionToken(id: UUID(), contractID: workID)
        DispatchQueue.main.async { selected = token }
    }

    // MARK: - Drop handling
    private func handleDrop(providers: [NSItemProvider], onto day: Date) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let s = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let payload = WorkAgendaDragPayload.parse(s) else { return }
            Task { @MainActor in
                switch payload {
                case .work(let id):
                    prompt = PlanPrompt(workID: id, date: AppCalendar.startOfDay(day))
                    // Tentatively sync the contract's scheduledDate; final save happens on prompt Save
                    let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
                    if let c = try? modelContext.fetch(fetch).first {
                        c.scheduledDate = AppCalendar.startOfDay(day)
                        _ = saveCoordinator.save(modelContext, reason: "Sync contract scheduledDate on drop (prompt pending)")
                    }
                case .checkIn(let id):
                    reschedulePlanItem(id: id, to: AppCalendar.startOfDay(day))
                    // Also update the linked contract's scheduledDate to match the moved plan item
                    let fetchPI = FetchDescriptor<WorkPlanItem>(predicate: #Predicate<WorkPlanItem> { $0.id == id })
                    if let item = try? modelContext.fetch(fetchPI).first,
                       let wid = item.workID.asUUID {
                        let fetchWC = FetchDescriptor<WorkContract>(predicate: #Predicate<WorkContract> { $0.id == wid })
                        if let c = try? modelContext.fetch(fetchWC).first {
                            c.scheduledDate = AppCalendar.startOfDay(day)
                            _ = saveCoordinator.save(modelContext, reason: "Sync contract scheduledDate on calendar move")
                        }
                    }
                }
            }
        }
        return true
    }

    // MARK: - Actions
    private func savePlan(workID: UUID, date: Date, reason: WorkPlanItem.Reason?, note: String) {
        let normalized = AppCalendar.startOfDay(date)
        let item = WorkPlanItem(workID: workID, scheduledDate: normalized, reason: reason, note: note.isEmpty ? nil : note)
        modelContext.insert(item)
        let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == workID })
        if let c = try? modelContext.fetch(fetch).first {
            c.scheduledDate = normalized
        }
        _ = saveCoordinator.save(modelContext, reason: "Create WorkPlanItem")
        #if DEBUG
        if let c = try? modelContext.fetch(fetch).first {
            let allItems = (try? modelContext.fetch(FetchDescriptor<WorkPlanItem>())) ?? []
            let desc = WorkAgingDebug.describe(contract: c, modelContext: modelContext, planItems: allItems)
            debugPrint("WorkAgingDebug(savePlan):", desc)
        }
        #endif
    }

    private func reschedulePlanItem(id: UUID, to day: Date) {
        let fetch = FetchDescriptor<WorkPlanItem>(predicate: #Predicate<WorkPlanItem> { $0.id == id })
        if let item = try? modelContext.fetch(fetch).first,
           let wid = item.workID.asUUID {
            item.scheduledDate = AppCalendar.startOfDay(day)
            let fetchWC = FetchDescriptor<WorkContract>(predicate: #Predicate<WorkContract> { $0.id == wid })
            if let c = try? modelContext.fetch(fetchWC).first {
                c.scheduledDate = AppCalendar.startOfDay(day)
            }
            _ = saveCoordinator.save(modelContext, reason: "Reschedule WorkPlanItem")
        }
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

