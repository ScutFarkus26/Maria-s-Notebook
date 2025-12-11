import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Observation

struct WorksPlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]) private var works: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]

    @AppStorage("WorkPlanningAgenda.startDate") private var startDateRaw: Double = 0

    @State private var viewModel = WorksPlanningViewModel(
        startDate: Date(),
        calendar: Calendar.current,
        isNonSchoolDay: { _ in false },
        checkInService: { WorkCheckInService(context: $0) }
    )

    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }

    private func workTitle(for work: WorkModel) -> String {
        let t = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if let slID = work.studentLessonID {
            let descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == slID })
            if let sl = (try? modelContext.fetch(descriptor))?.first,
               let l = lessonsByID[sl.lessonID] {
                return l.name
            }
        }
        return work.workType.rawValue
    }
    
    private func participantNames(for work: WorkModel) -> String {
        let names = work.participants.compactMap { p in
            studentsByID[p.studentID]?.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return names.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                agenda
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if startDateRaw != 0 {
                viewModel.startDate = Date(timeIntervalSince1970: startDateRaw)
            } else {
                viewModel.startDate = PlanningEngine.firstSchoolDay(
                    onOrAfter: calendar.startOfDay(for: .now),
                    calendar: calendar,
                    isNonSchoolDay: { SchoolCalendar.isNonSchoolDay($0, using: modelContext) }
                )
            }
            // Rebind closure to capture actual modelContext
            viewModel = WorksPlanningViewModel(
                startDate: viewModel.startDate,
                calendar: calendar,
                isNonSchoolDay: { day in SchoolCalendar.isNonSchoolDay(day, using: modelContext) },
                checkInService: { WorkCheckInService(context: $0) }
            )
        }
        .onChange(of: viewModel.startDate) { _, new in
            startDateRaw = new.timeIntervalSince1970
        }
        .sheet(item: $viewModel.activeSheet) { (sheet: ActiveSheet) in
            switch sheet {
            case .schedule(let id):
                ScheduleCheckInSheet(workID: id, initialDate: viewModel.scheduleDate,
                                     onCancel: { viewModel.activeSheet = nil },
                                     onSave: { date in
                    try? viewModel.scheduleCheckIn(for: id, on: date, context: modelContext)
                    viewModel.activeSheet = nil
                })
#if os(macOS)
                .frame(minWidth: 360)
#endif
            case .detail(let id):
                WorkDetailContainerView(workID: id) { viewModel.activeSheet = nil }
#if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizing(.fitted)
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
#endif
            }
        }
        .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        InboxSidebarView(
            unscheduledWorks: viewModel.unscheduledWorks(from: works),
            workTitle: { workTitle(for: $0) },
            participantNames: { participantNames(for: $0) },
            onOpen: { id in viewModel.activeSheet = .detail(workID: id) },
            onSchedule: { id in
                viewModel.scheduleDate = Date()
                viewModel.activeSheet = .schedule(workID: id)
            }
        )
    }

    private var header: some View {
        let days = viewModel.computeDays(window: UIConstants.planningWindowDays)
        let first = days.first ?? Date()
        let last = days.last ?? Date()
        return AgendaHeaderView(
            firstDate: first,
            lastDate: last,
            onPrev: {
                withAnimation {
                    viewModel.moveStart(bySchoolDays: -UIConstants.planningNavigationStepSchoolDays)
                }
            },
            onToday: {
                withAnimation {
                    viewModel.resetToFirstSchoolDay(from: calendar.startOfDay(for: .now))
                }
            },
            onNext: {
                withAnimation {
                    viewModel.moveStart(bySchoolDays: UIConstants.planningNavigationStepSchoolDays)
                }
            }
        )
    }

    private var agenda: some View {
        let days = viewModel.computeDays(window: UIConstants.planningWindowDays)
        let grouped = viewModel.groupedItems(works: works)

        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Day strip
                DayStripView(days: days) { day in
                    withAnimation {
                        proxy.scrollTo(viewModel.dayID(day), anchor: .top)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                Divider()

                // Scrollable agenda with pinned headers
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                        ForEach(days, id: \.self) { day in
                            Section(header: dayHeader(day)) {
                                VStack(spacing: 12) {
                                    ForEach(DayPeriod.allCases, id: \.self) { period in
                                        periodCard(day: day, period: period, grouped: grouped)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            }
                            .id(viewModel.dayID(day))
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .onChange(of: viewModel.startDate) { _, _ in
                if let firstDay = days.first {
                    withAnimation {
                        proxy.scrollTo(viewModel.dayID(firstDay), anchor: .top)
                    }
                }
            }
            .onAppear {
                if let firstDay = days.first {
                    proxy.scrollTo(viewModel.dayID(firstDay), anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func dayHeader(_ day: Date) -> some View {
        HStack(spacing: 10) {
            Text(viewModel.dayName(day))
                .font(.headline.weight(.semibold))
            Text(viewModel.dayNumber(day))
                .font(.title2.weight(.semibold))
            Spacer()
            if viewModel.isNonSchool(day) {
                Text("No School")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func periodChip(for period: DayPeriod) -> some View {
        let text = period.label
        let color = period.color
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.6), lineWidth: 1)
            )
            .fixedSize()
    }

    private func periodCard(day: Date, period: DayPeriod, grouped: [DayKey: [ScheduledItem]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            periodChip(for: period)
            WorkDropList(
                day: day,
                period: period,
                works: works,
                grouped: grouped,
                isNonSchool: viewModel.isNonSchool(day),
                namesForWork: { work in participantNames(for: work) },
                titleForWork: workTitle(for:)
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(alignment: .center) {
            if viewModel.isNonSchool(day) {
                Text("No School")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.black.opacity(0.35))
                    )
                    .offset(x: -80, y: 0)
            }
        }
    }

    private struct WorkDropList: View {
        @Environment(\.modelContext) private var modelContext
        @Environment(\.calendar) private var calendar

        let day: Date
        let period: DayPeriod
        let works: [WorkModel]
        let grouped: [DayKey: [ScheduledItem]]
        let isNonSchool: Bool
        let namesForWork: (WorkModel) -> String
        let titleForWork: (WorkModel) -> String
        let onOpenWork: (UUID) -> Void = { _ in }
        let onMarkCompleted: (WorkCheckIn) -> Void = { _ in }

        @State private var isTargeted: Bool = false
        @State private var insertionIndex: Int? = nil
        @State private var itemFrames: [UUID: CGRect] = [:]
        @State private var zoneSpaceID = UUID()

        var body: some View {
            let items = grouped[DayKey(dayStart: calendar.startOfDay(for: day), period: period)] ?? []

            ZStack(alignment: .topLeading) {
                // Background and targeted outline
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(isTargeted ? 0.08 : 0.04))
                if isTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.7), lineWidth: 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if items.isEmpty {
                        Text("No plans yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(items) { item in
                            rowView(for: item)
                                .draggable(PlanningDragItem.checkIn(item.checkIn.id)) {
                                    rowView(for: item).opacity(0.9)
                                }
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: PillFramePreference.self,
                                            value: [item.checkIn.id: proxy.frame(in: .named(zoneSpaceID))]
                                        )
                                    }
                                )
                        }
                    }
                }
                .padding(8)

                // Insertion indicator
                GeometryReader { proxy in
                    if let idx = insertionIndex {
                        let frames: [(UUID, CGRect)] = items.compactMap { it in
                            if let rect = itemFrames[it.checkIn.id] { return (it.checkIn.id, rect) }
                            return nil
                        }.sorted { $0.1.minY < $1.1.minY }

                        if frames.isEmpty {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 16, height: 3)
                                .position(x: proxy.size.width / 2, y: 8)
                        } else {
                            let y: CGFloat = (idx < frames.count) ? frames[idx].1.minY : (frames.last!.1.maxY + 8)
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 16, height: 3)
                                .position(x: proxy.size.width / 2, y: y)
                        }
                    }
                }
            }
            .coordinateSpace(name: zoneSpaceID)
            .onPreferenceChange(PillFramePreference.self) { frames in
                itemFrames = frames
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .dropDestination(for: PlanningDragItem.self) { items, location in
                guard let payload = items.first else { return false }
                handleTypedPayload(payload, locationY: location.y)
                return true
            }
            .disabled(isNonSchool)
        }

        @MainActor
        private func handleTypedPayload(_ payload: PlanningDragItem, locationY: CGFloat) {
            let current = getCurrent()
            let frames = itemFrames
            let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
                if let rect = frames[item.id] { return (item.id, rect) }
                return nil
            })
            let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: locationY, frames: dict)
            let baseDate = dateForSlot(day: day, period: period)

            switch payload.kind {
            case .work:
                if let work = works.first(where: { $0.id == payload.id }) {
                    let service = WorkCheckInService(context: modelContext)
                    if let newCI = try? service.createCheckIn(for: work, date: baseDate, status: .scheduled, purpose: "", note: "") {
                        applyOrder(currentIDs: current.map { $0.id }, inserting: newCI.id, baseDate: baseDate, insertionIndex: insertionIndex)
                    }
                }
            case .checkIn:
                applyOrder(currentIDs: current.map { $0.id }, inserting: payload.id, baseDate: baseDate, insertionIndex: insertionIndex)
            }
        }

        private func getCurrent() -> [ScheduledItem] {
            grouped[DayKey(dayStart: calendar.startOfDay(for: day), period: period)] ?? []
        }

        @MainActor
        private func applyOrder(currentIDs: [UUID], inserting id: UUID, baseDate: Date, insertionIndex: Int) {
            var ids = currentIDs
            ids.removeAll(where: { $0 == id })
            let bounded = max(0, min(insertionIndex, ids.count))
            ids.insert(id, at: bounded)
            let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: UIConstants.scheduleSpacingSeconds)
            let allCIs = works.flatMap { $0.checkIns }
            for id in ids {
                if let target = allCIs.first(where: { $0.id == id }) {
                    target.date = timeMap[id] ?? target.date
                    target.status = .scheduled
                }
            }
            try? modelContext.save()
        }

        private func dateForSlot(day: Date, period: DayPeriod) -> Date {
            let startOfDay = calendar.startOfDay(for: day)
            return calendar.date(byAdding: .hour, value: period.baseHour, to: startOfDay) ?? startOfDay
        }

        @ViewBuilder
        private func rowView(for item: ScheduledItem) -> some View {
            HStack(spacing: 10) {
                Image(systemName: "hammer")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleForWork(item.work))
                        .font(.callout.weight(.semibold))
                    let names = namesForWork(item.work)
                    if !names.isEmpty {
                        Text(names)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.checkIn.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Open Work", systemImage: "arrow.forward.circle") { onOpenWork(item.work.id) }
                    Button("Mark Completed", systemImage: "checkmark.circle") { onMarkCompleted(item.checkIn) }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
            .onTapGesture { onOpenWork(item.work.id) }
        }

        private struct PillFramePreference: PreferenceKey {
            static var defaultValue: [UUID: CGRect] = [:]
            static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
                value.merge(nextValue(), uniquingKeysWith: { $1 })
            }
        }
    }

    // Keep WorksInboxDropDelegate for now
}

// MARK: - Subviews

private struct InboxSidebarView: View {
    let unscheduledWorks: [WorkModel]
    let workTitle: (WorkModel) -> String
    let participantNames: (WorkModel) -> String
    let onOpen: (UUID) -> Void
    let onSchedule: (UUID) -> Void

    @State private var inboxIsTargeted: Bool = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inbox")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(unscheduledWorks.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(unscheduledWorks, id: \.id) { w in
                        Button {
                            onOpen(w.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "hammer")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workTitle(w))
                                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                    let names = participantNames(w)
                                    if !names.isEmpty {
                                        Text(names)
                                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(w.createdAt, style: .date)
                                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button("Open", systemImage: "arrow.forward.circle") { onOpen(w.id) }
                                    Button("Schedule Check-In", systemImage: "calendar.badge.plus") {
                                        onSchedule(w.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                        .draggable(PlanningDragItem.work(w.id)) {
                            HStack(spacing: 10) {
                                Image(systemName: "hammer").foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workTitle(w))
                                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                    let names = participantNames(w)
                                    if !names.isEmpty {
                                        Text(names)
                                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(w.createdAt, style: .date)
                                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
            }
            .dropDestination(for: PlanningDragItem.self) { items, _ in
                guard let item = items.first, item.kind == .checkIn else { return false }
                Task { @MainActor in
                    let fetch = FetchDescriptor<WorkCheckIn>(predicate: #Predicate { $0.id == item.id })
                    if let ci = (try? modelContext.fetch(fetch))?.first {
                        let svc = WorkCheckInService(context: modelContext)
                        if let parent = ci.work {
                            try? svc.delete(ci, from: parent)
                        } else {
                            try? svc.delete(ci)
                        }
                    }
                }
                return true
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(inboxIsTargeted ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )
            .onDrop(of: [UTType.text], isTargeted: $inboxIsTargeted) { _ in false }
        }
        .frame(width: 280)
    }
}

private struct AgendaHeaderView: View {
    let firstDate: Date
    let lastDate: Date
    let onPrev: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void

    var body: some View {
        let fmt: Date.FormatStyle = Date.FormatStyle()
            .month(.abbreviated)
            .day()
        HStack(spacing: 12) {
            Button {
                onPrev()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("\(firstDate.formatted(fmt)) - \(lastDate.formatted(fmt))")
                .font(.title3.weight(.semibold))

            Spacer()

            Button {
                onToday()
            } label: {
                Text("Today")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.borderless)

            Button {
                onNext()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

private struct DayStripView: View {
    let days: [Date]
    let onTap: (Date) -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(days, id: \.self) { day in
                    let label = day.formatted(Date.FormatStyle().weekday(.abbreviated).day())
                    Button {
                        onTap(day)
                    } label: {
                        Text(label)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Schema([Item.self, Student.self, Lesson.self, StudentLesson.self, WorkModel.self, WorkParticipantEntity.self, WorkCompletionRecord.self, AttendanceRecord.self, WorkCheckIn.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return WorksPlanningView()
        .modelContainer(container)
}

