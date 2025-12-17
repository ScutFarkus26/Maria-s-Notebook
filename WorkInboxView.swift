import SwiftUI
import SwiftData
import Combine

struct WorkInboxView: View {
    private enum GroupMode: String, CaseIterable, Identifiable { case byDate, byLesson; var id: String { rawValue } }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query private var contracts: [WorkContract]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @Query private var presentations: [Presentation]
    @AppStorage("WorkInboxView.groupMode") private var groupModeRaw: String = GroupMode.byDate.rawValue
    @State private var groupMode: GroupMode = .byDate
    @State private var searchText: String = ""

#if os(iOS)
    @State private var editMode: EditMode = .inactive
#else
    @State private var macEditing: Bool = false
#endif

    private var isEditing: Bool {
#if os(iOS)
        return editMode == .active
#else
        return macEditing
#endif
    }

    private struct SelectionToken: Identifiable, Equatable {
        let id: UUID
        let contractID: UUID
    }
    @State private var selected: SelectionToken? = nil
    @State private var selectedContractIDs = Set<UUID>()

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

    private func matchesSearch(_ c: WorkContract) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }

        var fields: [String] = []

        // Lesson fields: name, subject, group
        if let lid = UUID(uuidString: c.lessonID), let lesson = lessonsByID[lid] {
            fields.append(lesson.name)
            fields.append(lesson.subject)
            fields.append(lesson.group)
        }
        // Fallback lesson titles (including presentation snapshots)
        fields.append(lessonName(for: c))
        fields.append(lessonTitle(forLessonID: c.lessonID, presentationID: c.presentationID))

        // Student fields: first, last, full, and display name
        if let sid = UUID(uuidString: c.studentID), let s = studentsByID[sid] {
            fields.append(s.firstName)
            fields.append(s.lastName)
            fields.append(s.fullName)
            fields.append(StudentFormatter.displayName(for: s))
        } else {
            fields.append(studentName(for: c))
        }

        // Status badge text (e.g., Active, Review)
        fields.append(badge(for: c.status))

        // Normalize and match
        return fields.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains(q) }
    }

    private var filteredOpenContracts: [WorkContract] { openContracts.filter { matchesSearch($0) } }

    private var overdue: [WorkContract] {
        filteredOpenContracts.filter { c in
            if let d = c.scheduledDate { return d < startOfToday }
            return false
        }.sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }
    private var today: [WorkContract] {
        filteredOpenContracts.filter { c in
            if let d = c.scheduledDate { return calendar.isDate(d, inSameDayAs: startOfToday) }
            return false
        }.sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }
    private var upcoming: [WorkContract] {
        filteredOpenContracts.filter { c in
            if let d = c.scheduledDate { return d > startOfToday }
            return false
        }.sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }
    private var unscheduled: [WorkContract] {
        filteredOpenContracts.filter { $0.scheduledDate == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    @ViewBuilder
    private func listContent() -> some View {
        switch groupMode {
        case .byDate:
            if !overdue.isEmpty { section(title: "Overdue", items: overdue) }
            if !today.isEmpty { section(title: "Today", items: today) }
            if !upcoming.isEmpty { section(title: "Upcoming", items: upcoming) }
            if !unscheduled.isEmpty { section(title: "Unscheduled", items: unscheduled) }

            if overdue.isEmpty && today.isEmpty && upcoming.isEmpty && unscheduled.isEmpty {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("No work to show", systemImage: "tray")
                } else {
                    ContentUnavailableView("No results", systemImage: "magnifyingglass")
                }
            }

        case .byLesson:
            lessonGroupedSections()
        }
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

                ScrollView {
                    LazyVStack(spacing: 0) {
                        listContent()
                    }
                    .animation(nil, value: groupMode)
#if os(iOS)
                    .animation(nil, value: editMode)
#else
                    .animation(nil, value: macEditing)
#endif
                    .animation(nil, value: selectedContractIDs)
                }
                .navigationTitle("Work Inbox (Beta)")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            markSelectedComplete()
                        } label: {
                            Label("Mark Completed", systemImage: "checkmark.circle")
                        }
                        .disabled(selectedContractIDs.isEmpty)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        if isEditing {
                            Button("Cancel") {
                                selectedContractIDs.removeAll()
#if os(iOS)
                                withAnimation { editMode = .inactive }
#else
                                withAnimation { macEditing = false }
#endif
                            }
                        }
                    }
                    ToolbarItem(placement: .automatic) {
#if os(iOS)
                        EditButton()
#else
                        Button(isEditing ? "Done" : "Edit") {
                            withAnimation { macEditing.toggle() }
                        }
#endif
                    }
                }
#if os(iOS)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search by lesson, student, or status")
#else
                .searchable(text: $searchText, prompt: "Search by lesson, student, or status")
#endif
#if os(iOS)
                .environment(\.editMode, $editMode)
#endif
            }
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
            // Clear multi-selection when changing grouping to avoid stale IDs
            selectedContractIDs.removeAll()
        }
#if os(iOS)
        .onChange(of: editMode) { _, new in
            if new != .active {
                selectedContractIDs.removeAll()
            }
        }
#else
        .onChange(of: macEditing) { _, new in
            if !new {
                selectedContractIDs.removeAll()
            }
        }
#endif
    }

    @ViewBuilder
    private func section(title: String, items: [WorkContract]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            ForEach(items, id: \.id) { c in
                row(c)
            }
        }
    }

    @ViewBuilder
    private func lessonGroupedSections() -> some View {
        // Group open contracts by lessonID (string)
        let dict = Dictionary(grouping: filteredOpenContracts, by: { $0.lessonID })
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
                VStack(alignment: .leading, spacing: 0) {
                    Text(lessonTitle(forLessonID: group.lessonID, presentationID: group.items.first?.presentationID))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    ForEach(group.items, id: \.id) { c in
                        row(c)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ c: WorkContract) -> some View {
        let isSelected = selectedContractIDs.contains(c.id)
        HStack(spacing: 10) {
            // Reserved selection affordance space (constant width)
            Group {
                if isEditing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                } else {
                    Image(systemName: "circle")
                        .opacity(0)
                }
            }
            .frame(width: 24)

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
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 52, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                if isSelected { selectedContractIDs.remove(c.id) } else { selectedContractIDs.insert(c.id) }
            } else {
                selected = nil
                let token = SelectionToken(id: UUID(), contractID: c.id)
                DispatchQueue.main.async { selected = token }
            }
        }
#if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            swipeActions(for: c)
        }
#endif
        .contextMenu { contextMenu(for: c) }
        .transaction { $0.animation = nil }
        .animation(nil, value: selectedContractIDs)
#if os(iOS)
        .animation(nil, value: editMode)
#else
        .animation(nil, value: macEditing)
#endif
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
        _ = saveCoordinator.save(modelContext, reason: "Mark contract complete")
    }

    private func markSelectedComplete() {
        let ids = selectedContractIDs
        guard !ids.isEmpty else { return }
        let now = Date()
        let targets = contracts.filter { ids.contains($0.id) }
        for c in targets {
            c.status = .complete
            c.completedAt = now
            c.scheduledDate = nil
        }
        _ = saveCoordinator.save(modelContext, reason: "Bulk complete selected contracts")
        selectedContractIDs.removeAll()
#if os(iOS)
        withAnimation { editMode = .inactive }
#else
        withAnimation { macEditing = false }
#endif
    }

    private func setForToday(_ c: WorkContract) {
        c.scheduledDate = AppCalendar.startOfDay(Date())
        _ = saveCoordinator.save(modelContext, reason: "Schedule for today")
    }

    private func clearSchedule(_ c: WorkContract) {
        c.scheduledDate = nil
        _ = saveCoordinator.save(modelContext, reason: "Clear schedule")
    }

    private func moveToReview(_ c: WorkContract) {
        c.status = .review
        _ = saveCoordinator.save(modelContext, reason: "Move to review")
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
        .environmentObject(SaveCoordinator.preview)
}

