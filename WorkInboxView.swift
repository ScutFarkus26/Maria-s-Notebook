import SwiftUI
import SwiftData

struct WorkInboxView: View {
    private enum GroupMode: String, CaseIterable, Identifiable { case byDate, byLesson; var id: String { rawValue } }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query private var contracts: [WorkContract]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @Query private var presentations: [Presentation]
    @AppStorage("WorkInboxView.groupMode") private var groupModeRaw: String = GroupMode.byDate.rawValue
    @State private var groupMode: GroupMode = .byDate

    private struct SelectionToken: Identifiable, Equatable {
        let id: UUID
        let contractID: UUID
    }
    @State private var selected: SelectionToken? = nil

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    private var presentationsByID: [UUID: Presentation] { Dictionary(uniqueKeysWithValues: presentations.map { ($0.id, $0) }) }
    private var presentationsByLessonID: [String: Presentation] {
        var dict: [String: Presentation] = [:]
        for p in presentations { if dict[p.lessonID] == nil { dict[p.lessonID] = p } }
        return dict
    }

    private var startOfToday: Date { AppCalendar.startOfDay(Date()) }

    private var openContracts: [WorkContract] { contracts.filter { $0.status != .complete } }

    private var overdue: [WorkContract] {
        openContracts.filter { c in
            if let d = c.scheduledDate { return d < startOfToday }
            return false
        }.sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }
    private var today: [WorkContract] {
        openContracts.filter { c in
            if let d = c.scheduledDate { return calendar.isDate(d, inSameDayAs: startOfToday) }
            return false
        }.sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }
    private var upcoming: [WorkContract] {
        openContracts.filter { c in
            if let d = c.scheduledDate { return d > startOfToday }
            return false
        }.sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }
    private var unscheduled: [WorkContract] {
        openContracts.filter { $0.scheduledDate == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                // Grouping control
                Picker("Grouping", selection: $groupMode) {
                    Text("By Date").tag(GroupMode.byDate)
                    Text("By Lesson").tag(GroupMode.byLesson)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 8)

                List {
#if DEBUG
                    // DEBUG diagnostics: show total and open counts
                    let total = contracts.count
                    let open = contracts.filter { $0.status != .complete }.count
                    Text("DEBUG: WorkContracts total = \(total), open = \(open)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
#endif

                    switch groupMode {
                    case .byDate:
                        if !overdue.isEmpty { section(title: "Overdue", items: overdue) }
                        if !today.isEmpty { section(title: "Today", items: today) }
                        if !upcoming.isEmpty { section(title: "Upcoming", items: upcoming) }
                        if !unscheduled.isEmpty { section(title: "Unscheduled", items: unscheduled) }

#if DEBUG
                        if openContracts.isEmpty == false {
                            Section("All Open Work (DEBUG)") {
                                ForEach(openContracts) { c in
                                    Button {
                                        selected = nil
                                        let token = SelectionToken(id: UUID(), contractID: c.id)
                                        DispatchQueue.main.async { selected = token }
                                    } label: { row(c) }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) { swipeActions(for: c) }
                                    .contextMenu { contextMenu(for: c) }
                                }
                            }
                        }
#endif

                        if overdue.isEmpty && today.isEmpty && upcoming.isEmpty && unscheduled.isEmpty {
                            ContentUnavailableView("No work to show", systemImage: "tray")
                        }

                    case .byLesson:
                        lessonGroupedSections()
                    }
                }
#if os(iOS)
                .listStyle(.insetGrouped)
#else
                .listStyle(.inset)
#endif
            }
            .navigationTitle("Work Inbox (Beta)")
        }
        .sheet(item: $selected, onDismiss: { selected = nil }) { token in
            if let c = contracts.first(where: { $0.id == token.contractID }) {
                WorkContractDetailSheet(contract: c) { selected = nil }
                    .id(token.id)
            } else {
                ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear {
            if let m = GroupMode(rawValue: groupModeRaw) { groupMode = m }
        }
        .onChange(of: groupMode) { _, new in
            groupModeRaw = new.rawValue
        }
    }

    @ViewBuilder
    private func section(title: String, items: [WorkContract]) -> some View {
        Section(title) {
            ForEach(items) { c in
                Button {
                    selected = nil
                    let token = SelectionToken(id: UUID(), contractID: c.id)
                    DispatchQueue.main.async { selected = token }
                } label: { row(c) }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) { swipeActions(for: c) }
                .contextMenu { contextMenu(for: c) }
            }
        }
    }

    @ViewBuilder
    private func lessonGroupedSections() -> some View {
        // Group open contracts by lessonID (string)
        let dict = Dictionary(grouping: openContracts, by: { $0.lessonID })
        let result: [(lessonID: String, items: [WorkContract])] = dict.map { (lessonID: $0.key, items: $0.value.sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }) }

        // Sort sections by earliest scheduled date (nil last), then title
        let sorted: [(lessonID: String, items: [WorkContract])] = result.sorted { lhs, rhs in
            let lmin = lhs.items.compactMap { $0.scheduledDate }.min()
            let rmin = rhs.items.compactMap { $0.scheduledDate }.min()
            if lmin != rmin {
                if lmin == nil { return false }
                if rmin == nil { return true }
                return lmin! < rmin!
            }
            let lt = lessonTitle(forLessonID: lhs.lessonID, presentationID: lhs.items.first?.presentationID)
            let rt = lessonTitle(forLessonID: rhs.lessonID, presentationID: rhs.items.first?.presentationID)
            return lt.localizedCaseInsensitiveCompare(rt) == .orderedAscending
        }

        if sorted.isEmpty {
            ContentUnavailableView("No work to show", systemImage: "tray")
        } else {
            ForEach(sorted, id: \.lessonID) { group in
                Section(header: Text(lessonTitle(forLessonID: group.lessonID, presentationID: group.items.first?.presentationID))) {
                    ForEach(group.items) { c in
                        Button {
                            selected = nil
                            let token = SelectionToken(id: UUID(), contractID: c.id)
                            DispatchQueue.main.async { selected = token }
                        } label: { row(c) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { swipeActions(for: c) }
                        .contextMenu { contextMenu(for: c) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ c: WorkContract) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: c.status))
                .foregroundStyle(color(for: c.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(lessonName(for: c))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(studentName(for: c))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let d = c.scheduledDate {
                Text(d, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(badge(for: c.status))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(color(for: c.status).opacity(0.15)))
        }
        .padding(6)
    }

    private func lessonName(for c: WorkContract) -> String {
        if let lid = UUID(uuidString: c.lessonID), let lesson = lessonsByID[lid] {
            let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return "Lesson"
    }

    private func studentName(for c: WorkContract) -> String {
        if let sid = UUID(uuidString: c.studentID), let s = studentsByID[sid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    private func lessonTitle(forLessonID lessonID: String, presentationID: String?) -> String {
        if let lid = UUID(uuidString: lessonID), let lesson = lessonsByID[lid] {
            let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if let pid = presentationID.flatMap(UUID.init(uuidString:)), let p = presentationsByID[pid] {
            let snap = (p.lessonTitleSnapshot ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !snap.isEmpty { return snap }
        }
        if let p2 = presentationsByLessonID[lessonID] {
            let snap = (p2.lessonTitleSnapshot ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !snap.isEmpty { return snap }
        }
        let short = String(lessonID.prefix(6))
        return "Lesson \(short)"
    }

    @ViewBuilder
    private func swipeActions(for c: WorkContract) -> some View {
        Button {
            markComplete(c)
        } label: { Label("Complete", systemImage: "checkmark.circle") }
        .tint(.green)

        Button {
            setForToday(c)
        } label: { Label("Set for Today", systemImage: "calendar") }
        .tint(.blue)

        Button(role: .destructive) {
            clearSchedule(c)
        } label: { Label("Clear", systemImage: "xmark.circle") }

        Button {
            moveToReview(c)
        } label: { Label("Move to Review", systemImage: "eye") }
        .tint(.orange)
    }

    @ViewBuilder
    private func contextMenu(for c: WorkContract) -> some View {
        Button("Mark Complete", systemImage: "checkmark.circle") { markComplete(c) }
        Button("Set for Today", systemImage: "calendar") { setForToday(c) }
        Button("Clear Schedule", systemImage: "xmark.circle") { clearSchedule(c) }
        Button("Move to Review", systemImage: "eye") { moveToReview(c) }
    }

    private func markComplete(_ c: WorkContract) {
        c.status = .complete
        c.completedAt = Date()
        c.scheduledDate = nil
        try? modelContext.save()
    }

    private func setForToday(_ c: WorkContract) {
        c.scheduledDate = AppCalendar.startOfDay(Date())
        try? modelContext.save()
    }

    private func clearSchedule(_ c: WorkContract) {
        c.scheduledDate = nil
        try? modelContext.save()
    }

    private func moveToReview(_ c: WorkContract) {
        c.status = .review
        try? modelContext.save()
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

    private func badge(for status: WorkStatus) -> String {
        switch status {
        case .active: return "Active"
        case .review: return "Review"
        case .complete: return "Complete"
        }
    }
}

#Preview {
    let schema = AppSchema.schema
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    let ctx = container.mainContext

    let student = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
    let lesson = Lesson(name: "Long Division", subject: "Math", group: "Operations", subheading: "", writeUp: "")
    let p = Presentation(presentedAt: Date(), lessonID: lesson.id.uuidString, studentIDs: [student.id.uuidString])
    ctx.insert(student); ctx.insert(lesson); ctx.insert(p)
    let c1 = WorkContract(studentID: student.id.uuidString, lessonID: lesson.id.uuidString, presentationID: p.id.uuidString, status: .active)
    let c2 = WorkContract(studentID: student.id.uuidString, lessonID: lesson.id.uuidString, presentationID: p.id.uuidString, status: .review, scheduledDate: Date())
    ctx.insert(c1); ctx.insert(c2)

    return WorkInboxView()
        .previewEnvironment(using: container)
}
