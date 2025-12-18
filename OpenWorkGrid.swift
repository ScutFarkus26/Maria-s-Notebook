import SwiftUI
import SwiftData

struct OpenWorkGrid: View {
    let works: [WorkContract]
    let lessonsByID: [UUID: Lesson]
    let studentsByID: [UUID: Student]
    let sortMode: WorkAgendaSortMode

    let onOpen: (WorkContract) -> Void
    let onMarkCompleted: (WorkContract) -> Void
    let onScheduleToday: (WorkContract) -> Void

    // MARK: - Layout
    // Choose 1 or 2 columns based on available width; never create 3+
    private func columns(for width: CGFloat) -> [GridItem] {
        return Array(repeating: GridItem(.flexible(minimum: 180, maximum: .infinity), spacing: 12), count: 4)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns(for: proxy.size.width), alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedSections, id: \.key) { section in
                        Section(header: groupHeader(title: section.key, count: section.items.count)) {
                            ForEach(section.items, id: \.id) { item in
                                WorkCardView(
                                    contract: item.contract,
                                    lessonTitle: item.title,
                                    studentDisplay: item.student,
                                    needsAttention: item.needsAttention,
                                    metadata: item.metadata,
                                    onOpen: onOpen,
                                    onMarkCompleted: onMarkCompleted,
                                    onScheduleToday: onScheduleToday
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func groupHeader(title: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Derived items
    private struct Item: Identifiable { let id = UUID(); let _id: UUID; let contract: WorkContract; let title: String; let student: String; let needsAttention: Bool; let metadata: String }

    // Group items by current sort mode; preserve overall order by grouping in the order items first appear
    private var groupedSections: [(key: String, items: [Item])] {
        let items = sortedWorks
        var order: [String] = []
        var buckets: [String: [Item]] = [:]
        for it in items {
            let key = groupKey(for: it)
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(it)
        }
        return order.map { key in (key: key, items: buckets[key] ?? []) }
    }

    private func groupKey(for item: Item) -> String {
        switch sortMode {
        case .lesson:
            return item.title
        case .student:
            return item.student
        case .age:
            let days = ageDays(for: item.contract)
            return ageBucketLabel(forDays: days)
        case .needsAttention:
            return item.needsAttention ? "Needs Attention" : "Other"
        }
    }

    private func ageBucketLabel(forDays days: Int) -> String {
        if days <= 0 { return "Today" }
        else if days <= 3 { return "1–3 days" }
        else if days <= 7 { return "4–7 days" }
        else if days <= 14 { return "8–14 days" }
        else if days <= 30 { return "15–30 days" }
        else { return "30+ days" }
    }

    private var sortedWorks: [Item] {
        let mapped: [Item] = works.map { c in
            let title = lessonTitle(forLessonID: c.lessonID)
            let student = studentName(for: c)
            let meta = metadata(for: c)
            let attention = needsAttention(for: c)
            return Item(_id: c.id, contract: c, title: title, student: student, needsAttention: attention, metadata: meta)
        }
        switch sortMode {
        case .lesson:
            return mapped.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .student:
            return mapped.sorted { $0.student.localizedCaseInsensitiveCompare($1.student) == .orderedAscending }
        case .age:
            return mapped.sorted { ageDays(for: $0.contract) > ageDays(for: $1.contract) }
        case .needsAttention:
            return mapped.sorted { lhs, rhs in
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention && !rhs.needsAttention }
                // If both same attention, older first
                return ageDays(for: lhs.contract) > ageDays(for: rhs.contract)
            }
        }
    }

    // MARK: - Helpers
    private func lessonTitle(forLessonID lessonID: String) -> String {
        if let lid = UUID(uuidString: lessonID), let lesson = lessonsByID[lid] {
            let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(lessonID.prefix(6)))"
    }

    private func studentName(for c: WorkContract) -> String {
        if let sid = UUID(uuidString: c.studentID), let s = studentsByID[sid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    private func metadata(for c: WorkContract) -> String {
        var parts: [String] = []
        switch c.status {
        case .active: parts.append("Practice")
        case .review: parts.append("Follow-Up")
        case .complete: parts.append("Completed")
        }
        let age = ageDays(for: c)
        parts.append("\(age)d")
        return parts.joined(separator: " • ")
    }

    private func ageDays(for c: WorkContract) -> Int {
        let start = AppCalendar.startOfDay(c.createdAt)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }

    private func needsAttention(for c: WorkContract) -> Bool {
        // Conservative heuristic: overdue if scheduledDate in past, or stale if createdAt older than 10 days and no schedule.
        if let sd = c.scheduledDate {
            let today = AppCalendar.startOfDay(Date())
            if AppCalendar.startOfDay(sd) < today { return true }
        }
        let age = ageDays(for: c)
        if age >= 10 { return true }
        return false
    }
}

#Preview {
    let schema = AppSchema.schema
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    let ctx = container.mainContext
    let s = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
    let l = Lesson(name: "Long Division", subject: "Math", group: "Ops", subheading: "", writeUp: "")
    ctx.insert(s); ctx.insert(l)
    let c1 = WorkContract(studentID: s.id.uuidString, lessonID: l.id.uuidString, presentationID: nil, status: .active)
    let c2 = WorkContract(studentID: s.id.uuidString, lessonID: l.id.uuidString, presentationID: nil, status: .review)
    return OpenWorkGrid(
        works: [c1, c2],
        lessonsByID: [l.id: l],
        studentsByID: [s.id: s],
        sortMode: .lesson,
        onOpen: { _ in },
        onMarkCompleted: { _ in },
        onScheduleToday: { _ in }
    )
    .previewEnvironment(using: container)
}
