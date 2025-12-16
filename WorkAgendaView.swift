import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WorkAgendaView: View {
    // MARK: Environment / Queries
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query(filter: #Predicate<WorkContract> { $0.statusRaw != "complete" })
    private var contracts: [WorkContract]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    // MARK: State
    @AppStorage("WorkAgendaBeta.startDate") private var startDateRaw: Double = 0
    @State private var startDate: Date = Date()
    @State private var activeContract: WorkContract? = nil

    // DEBUG timing
    #if DEBUG
    @State private var debugLoadStart: Date = Date()
    #endif

    // MARK: Caches
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    private func isNonSchoolDay(_ day: Date) -> Bool {
        SchoolCalendar.isNonSchoolDay(day, using: modelContext)
    }

    private var days: [Date] {
        var result: [Date] = []
        var cursor = AppCalendar.startOfDay(startDate)
        while result.count < 7 {
            if !isNonSchoolDay(cursor) { result.append(cursor) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    // MARK: Buckets
    private var todayStart: Date { AppCalendar.startOfDay(Date()) }
    private var unscheduled: [WorkContract] {
        contracts.filter { $0.scheduledDate == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func scheduled(on day: Date) -> [WorkContract] {
        let d = AppCalendar.startOfDay(day)
        return contracts.filter { c in
            if let s = c.scheduledDate { return AppCalendar.startOfDay(s) == d } else { return false }
        }
        .sorted { lhs, rhs in
            (lhs.createdAt) < (rhs.createdAt)
        }
    }

    // MARK: - Body
    var body: some View {
        UnifiedAgendaView(
            startDate: startDate,
            days: days,
            isNonSchoolDay: { day in isNonSchoolDay(day) },
            onPrev: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = AgendaSchoolDayRules.movedStart(bySchoolDays: -7, from: startDate, calendar: calendar, isNonSchoolDay: { isNonSchoolDay($0) })
                }
            },
            onNext: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = AgendaSchoolDayRules.movedStart(bySchoolDays: 7, from: startDate, calendar: calendar, isNonSchoolDay: { isNonSchoolDay($0) })
                }
            },
            onToday: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = AgendaSchoolDayRules.computeInitialStartDate(calendar: calendar, isNonSchoolDay: { isNonSchoolDay($0) })
                }
            },
            sidebar: { sidebar },
            headerActions: { EmptyView() }
        ) { day in
            dayBody(day)
        }
        .sheet(item: $activeContract) { c in
            WorkContractDetailSheet(contract: c) { activeContract = nil }
        }
        .onAppear {
            #if DEBUG
            debugLoadStart = Date()
            #endif
            if startDateRaw == 0 {
                startDate = AgendaSchoolDayRules.computeInitialStartDate(calendar: calendar, isNonSchoolDay: { isNonSchoolDay($0) })
                startDateRaw = startDate.timeIntervalSinceReferenceDate
            } else {
                startDate = Date(timeIntervalSinceReferenceDate: startDateRaw)
            }
            #if DEBUG
            let elapsed = Date().timeIntervalSince(debugLoadStart)
            print(String(format: "[WorkAgenda(Beta)] Initial load: %d open contracts in %.2f ms", contracts.count, elapsed * 1000))
            #endif
        }
        .onChange(of: startDate) { _, new in
            startDateRaw = new.timeIntervalSinceReferenceDate
        }
    }

    // MARK: - Sidebar (Inbox)
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inbox")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(unscheduled.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(unscheduled, id: \.id) { c in
                        Button {
                            activeContract = c
                        } label: {
                            WorkContractPill(
                                contract: c,
                                lessonTitle: lessonTitle(for: c),
                                studentName: studentName(for: c),
                                tint: subjectColor(for: c),
                                showDateBadge: false
                            )
                            .padding(10)
                        }
                        .buttonStyle(.plain)
                        .draggable(c.id.uuidString) {
                            WorkContractPill(
                                contract: c,
                                lessonTitle: lessonTitle(for: c),
                                studentName: studentName(for: c),
                                tint: subjectColor(for: c),
                                showDateBadge: false
                            )
                            .opacity(0.9)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
            .onDrop(of: [UTType.text], delegate: WorkContractInboxDropDelegate(modelContext: modelContext))
        }
    }

    // MARK: - Day content
    @ViewBuilder
    private func dayBody(_ day: Date) -> some View {
        let items = scheduled(on: day)
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("No plans yet")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
            } else {
                ForEach(items, id: \.id) { c in
                    WorkContractPill(
                        contract: c,
                        lessonTitle: lessonTitle(for: c),
                        studentName: studentName(for: c),
                        tint: subjectColor(for: c),
                        showDateBadge: false
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { activeContract = c }
                    .draggable(c.id.uuidString) {
                        WorkContractPill(
                            contract: c,
                            lessonTitle: lessonTitle(for: c),
                            studentName: studentName(for: c),
                            tint: subjectColor(for: c),
                            showDateBadge: false
                        )
                        .opacity(0.9)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onDrop(of: [UTType.text], delegate: WorkContractDayDropDelegate(modelContext: modelContext, day: day))
    }

    // MARK: - Helpers
    private func lessonTitle(for c: WorkContract) -> String {
        if let lid = UUID(uuidString: c.lessonID), let l = lessonsByID[lid] {
            let trimmed = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let short = c.lessonID.split(separator: "-").first.map(String.init) ?? "Lesson"
        return short.isEmpty ? "Lesson" : short
    }

    private func studentName(for c: WorkContract) -> String {
        if let sid = UUID(uuidString: c.studentID), let s = studentsByID[sid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    private func subjectColor(for c: WorkContract) -> Color {
        if let lid = UUID(uuidString: c.lessonID), let l = lessonsByID[lid] {
            return AppColors.color(forSubject: l.subject)
        }
        return .accentColor
    }
}

// MARK: - Pill
private struct WorkContractPill: View {
    let contract: WorkContract
    let lessonTitle: String
    let studentName: String
    let tint: Color
    var showDateBadge: Bool = false

    private var statusText: String? {
        switch contract.status {
        case .active: return "Active"
        case .review: return "Review"
        case .complete: return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Leading subject dot to mirror Lessons pill
            Rectangle()
                .fill(tint)
                .frame(width: UIConstants.ageIndicatorWidth)
                .opacity(1.0)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lessonTitle)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(studentName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let status = statusText {
                    Text(status)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

// MARK: - Drop Delegates
private struct WorkContractDayDropDelegate: DropDelegate {
    let modelContext: ModelContext
    let day: Date

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.text]) }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.text])
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let raw = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = UUID(uuidString: raw) else { return }
            Task { @MainActor in
                let start = Date()
                if let c = fetchContract(id, using: modelContext) {
                    c.scheduledDate = AppCalendar.startOfDay(day)
                    try? modelContext.save()
                    #if DEBUG
                    let elapsed = Date().timeIntervalSince(start)
                    print(String(format: "[WorkAgenda(Beta)] Drop to day: %@ in %.2f ms", id.uuidString, elapsed * 1000))
                    #endif
                }
            }
        }
        return true
    }
}

private struct WorkContractInboxDropDelegate: DropDelegate {
    let modelContext: ModelContext

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.text]) }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.text])
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let raw = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = UUID(uuidString: raw) else { return }
            Task { @MainActor in
                let start = Date()
                if let c = fetchContract(id, using: modelContext) {
                    c.scheduledDate = nil
                    try? modelContext.save()
                    #if DEBUG
                    let elapsed = Date().timeIntervalSince(start)
                    print(String(format: "[WorkAgenda(Beta)] Drop to inbox: %@ in %.2f ms", id.uuidString, elapsed * 1000))
                    #endif
                }
            }
        }
        return true
    }
}

// MARK: - Fetch helper
@MainActor
private func fetchContract(_ id: UUID, using context: ModelContext) -> WorkContract? {
    let desc = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
    return (try? context.fetch(desc))?.first
}

#Preview {
    let schema = AppSchema.schema
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    let ctx = container.mainContext

    // Seed preview data
    let student = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
    let lesson = Lesson(name: "Long Division", subject: "Math", group: "Operations", subheading: "", writeUp: "")
    ctx.insert(student); ctx.insert(lesson)
    let today = AppCalendar.startOfDay(Date())
    let c1 = WorkContract(studentID: student.id.uuidString, lessonID: lesson.id.uuidString, status: .active, scheduledDate: nil)
    let c2 = WorkContract(studentID: student.id.uuidString, lessonID: lesson.id.uuidString, status: .review, scheduledDate: today)
    ctx.insert(c1); ctx.insert(c2)

    return WorkAgendaView()
        .previewEnvironment(using: container)
}
