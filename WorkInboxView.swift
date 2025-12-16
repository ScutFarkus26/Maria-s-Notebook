import SwiftUI
import SwiftData

struct WorkInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query private var contracts: [WorkContract]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    @State private var selected: WorkContract? = nil

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

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
            List {
                if !overdue.isEmpty { section(title: "Overdue", items: overdue) }
                if !today.isEmpty { section(title: "Today", items: today) }
                if !upcoming.isEmpty { section(title: "Upcoming", items: upcoming) }
                if !unscheduled.isEmpty { section(title: "Unscheduled", items: unscheduled) }
                if overdue.isEmpty && today.isEmpty && upcoming.isEmpty && unscheduled.isEmpty {
                    ContentUnavailableView("No work to show", systemImage: "tray")
                }
            }
            .navigationTitle("Work Inbox (Beta)")
        }
        .sheet(item: $selected) { c in
            WorkContractDetailSheet(contract: c) { selected = nil }
        }
    }

    @ViewBuilder
    private func section(title: String, items: [WorkContract]) -> some View {
        Section(title) {
            ForEach(items) { c in
                Button { selected = c } label: { row(c) }
                    .buttonStyle(.plain)
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
    let schema = Schema([
        Item.self,
        Student.self,
        Lesson.self,
        StudentLesson.self,
        WorkContract.self,
        Presentation.self
    ])
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
