// WorkAgendaBetaView.swift
// Split layout: Top inbox of open works, Bottom planning calendar. Drag from inbox to calendar. Pills reschedulable.

import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct WorkAgendaBetaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @StateObject private var vm = WorkAgendaBetaViewModel()
    private struct SelectionToken: Identifiable, Equatable { let id: UUID; let contractID: UUID }
    @State private var selected: SelectionToken? = nil

    // Cached lookups to enrich rows without heavy traversal
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    @State private var planPrompt: PlanPrompt? = nil

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    private struct PlanPrompt: Identifiable {
        let id = UUID()
        let workID: UUID
        let date: Date
        var reason: WorkPlanItem.Reason = .progressCheck
        var note: String = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top panel: Open Works Inbox
            inboxPanel
            Divider()
            // Bottom panel: Planning Calendar
            calendarPanel
        }
        .sheet(item: $planPrompt) { prompt in
            PlanPromptSheetView(prompt: prompt) { planPrompt = nil } onSave: { reason, note in
                savePlan(workID: prompt.workID, date: prompt.date, reason: reason, note: note)
                planPrompt = nil
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
        .onAppear {
            AppCalendar.adopt(timeZoneFrom: calendar)
            if vm.startDate == .distantPast { vm.resetToToday(using: modelContext) }
        }
    }

    // MARK: - Inbox
    private var inboxPanel: some View {
        let all = vm.fetchOpenWorks(context: modelContext)
        // Build searchable text provider: lesson title + all related student names
        let searchable: (WorkContract) -> [String] = { wc in
            var fields: [String] = []
            // Lesson title
            fields.append(lessonTitle(forLessonID: wc.lessonID, presentationID: wc.presentationID))
            // Student names: first, last, full display name for the primary student
            if let sid = UUID(uuidString: wc.studentID), let s = studentsByID[sid] {
                fields.append(s.firstName)
                fields.append(s.lastName)
                fields.append(s.fullName)
                fields.append(StudentFormatter.displayName(for: s))
            }
            return fields
        }
        let works = vm.filtered(all, searchableTextProvider: searchable)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Open Works Inbox")
                    .font(.title3.weight(.semibold))
                Spacer()
                Picker("Filter", selection: $vm.quickFilter) {
                    ForEach(WorkAgendaBetaViewModel.QuickFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search students or lessons", text: $vm.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            if works.isEmpty {
                ContentUnavailableView("No open work", systemImage: "tray")
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(works, id: \.id) { c in
                            inboxRow(c)
                                .draggable(PlanningDragItem.work(c.id)) {
                                    inboxRow(c).opacity(0.9)
                                }
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .frame(maxHeight: 280) // keep inbox always visible
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func inboxRow(_ c: WorkContract) -> some View {
        let title = lessonTitle(forLessonID: c.lessonID, presentationID: c.presentationID)
        let student = studentName(for: c)
        let ageDays = daysSince(c.createdAt)
        HStack(spacing: 10) {
            Image(systemName: iconName(for: c.status))
                .foregroundStyle(color(for: c.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(student)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(ageDays)d")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ageDays > 14 ? .red : (ageDays > 7 ? .orange : .secondary))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .accessibilityLabel("Age in days: \(ageDays)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            selected = nil
            let token = SelectionToken(id: UUID(), contractID: c.id)
            DispatchQueue.main.async { selected = token }
        }
    }

    // MARK: - Calendar
    private var calendarPanel: some View {
        let days = vm.schoolDays(count: 10, using: modelContext) // 2 weeks horizon
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Work Planning Calendar")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Today") { vm.resetToToday(using: modelContext) }
                Button(action: { vm.previousWeek(using: modelContext) }) { Image(systemName: "chevron.left") }
                Button(action: { vm.nextWeek(using: modelContext) }) { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(days, id: \.self) { day in
                        dayColumn(day)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func dayColumn(_ day: Date) -> some View {
        let (start, end) = AppCalendar.dayRange(for: day)
        let items = vm.fetchPlanItems(in: start..<end, context: modelContext)
        VStack(alignment: .leading, spacing: 8) {
            Text(day.formatted(Date.FormatStyle().weekday(.abbreviated).day()))
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.id) { item in
                    pill(item)
                        .draggable(PlanningDragItem.checkIn(item.id)) {
                            pill(item).opacity(0.9)
                        }
                }
            }
            .padding(8)
            .frame(width: 260, alignment: .topLeading)
            .frame(minHeight: 160, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                handleDrop(providers: providers, onto: day)
            }
        }
    }

    private func pill(_ item: WorkPlanItem) -> some View {
        let title = workTitle(for: item.workID)
        return HStack(spacing: 6) {
            if let r = item.reason { Image(systemName: r.icon).foregroundStyle(.secondary) }
            Text(title)
                .font(.callout)
                .foregroundStyle(.primary)
            if let r = item.reason { Text(r.label).font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            Menu {
                Button("Open", systemImage: "arrow.forward.circle") {
                    selected = nil
                    let token = SelectionToken(id: UUID(), contractID: item.workID)
                    DispatchQueue.main.async { selected = token }
                }
                Button("Delete", role: .destructive, action: { deletePlan(item) })
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    }

    // MARK: - Drop handling
    private func handleDrop(providers: [NSItemProvider], onto day: Date) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let s = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: PlanningDragItem?
            if s.hasPrefix("WORK:"), let id = UUID(uuidString: String(s.dropFirst(5))) {
                payload = .work(id)
            } else if s.hasPrefix("CHECKIN:"), let id = UUID(uuidString: String(s.dropFirst(8))) {
                payload = .checkIn(id)
            } else if let id = UUID(uuidString: s) {
                payload = .checkIn(id)
            } else {
                payload = nil
            }
            guard let payload else { return }
            Task { @MainActor in
                switch payload.kind {
                case .work:
                    let normalized = AppCalendar.startOfDay(day)
                    planPrompt = PlanPrompt(workID: payload.id, date: normalized)
                case .checkIn:
                    // Treat as reschedule of existing plan item
                    reschedulePlanItem(id: payload.id, to: AppCalendar.startOfDay(day))
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
        _ = saveCoordinator.save(modelContext, reason: "Create WorkPlanItem")
    }

    private func reschedulePlanItem(id: UUID, to day: Date) {
        let fetch = FetchDescriptor<WorkPlanItem>(predicate: #Predicate { $0.id == id })
        if let item = try? modelContext.fetch(fetch).first {
            item.scheduledDate = AppCalendar.startOfDay(day)
            _ = saveCoordinator.save(modelContext, reason: "Reschedule WorkPlanItem")
        }
    }

    private func deletePlan(_ item: WorkPlanItem) {
        modelContext.delete(item)
        _ = saveCoordinator.save(modelContext, reason: "Delete WorkPlanItem")
    }

    // MARK: - Formatting helpers (copied from WorkInboxView)
    private func lessonTitle(forLessonID lessonID: String, presentationID: String?) -> String {
        if let lid = UUID(uuidString: lessonID), let lesson = lessonsByID[lid] {
            let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        // Fallback to presentation snapshots are not available for WorkContract here
        let short = String(lessonID.prefix(6))
        return "Lesson \(short)"
    }

    private func studentName(for c: WorkContract) -> String {
        if let sid = UUID(uuidString: c.studentID), let s = studentsByID[sid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    private func workTitle(for id: UUID) -> String {
        // Try to resolve from WorkContract
        let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
        if let c = try? modelContext.fetch(fetch).first {
            return lessonTitle(forLessonID: c.lessonID, presentationID: c.presentationID)
        }
        return "Work"
    }

    private func iconName(for status: WorkStatus) -> String {
        switch status {
        case .active: return "hammer"
        case .review: return "eye"
        case .complete: return "checkmark.circle"
        }
    }

    private func color(for status: WorkStatus) -> Color {
        switch status {
        case .active: return .purple
        case .review: return .orange
        case .complete: return .green
        }
    }

    private func daysSince(_ date: Date) -> Int {
        let start = AppCalendar.startOfDay(date)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }

    private struct PlanPromptSheetView: View {
        let prompt: PlanPrompt
        let onCancel: () -> Void
        let onSave: (WorkPlanItem.Reason, String) -> Void
        @State private var reason: WorkPlanItem.Reason = .progressCheck
        @State private var note: String = ""
        init(prompt: PlanPrompt, onCancel: @escaping () -> Void, onSave: @escaping (WorkPlanItem.Reason, String) -> Void) {
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
            .presentationSizing(.fitted)
            #endif
        }
    }
}

#Preview {
    let schema = AppSchema.schema
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    let ctx = container.mainContext

    // Seed minimal data
    let s = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
    let l = Lesson(name: "Long Division", subject: "Math", group: "Ops", subheading: "", writeUp: "")
    ctx.insert(s); ctx.insert(l)
    let c = WorkContract(studentID: s.id.uuidString, lessonID: l.id.uuidString, presentationID: nil, status: .active)
    ctx.insert(c)

    return WorkAgendaBetaView()
        .previewEnvironment(using: container)
        .environmentObject(SaveCoordinator.preview)
}

