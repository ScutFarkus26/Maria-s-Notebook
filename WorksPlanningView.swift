import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WorksPlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]) private var works: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]

    private enum ActiveSheet: Identifiable, Equatable {
        case schedule(workID: UUID)
        case detail(workID: UUID)
        var id: String {
            switch self {
            case .schedule(let id): return "schedule-\(id)"
            case .detail(let id): return "detail-\(id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet? = nil

    @State private var scheduleDate: Date = Date()
    @State private var inboxIsTargeted: Bool = false

    @AppStorage("WorkPlanningAgenda.startDate") private var startDateRaw: Double = 0
    @State private var startDate: Date = Date()

    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }

    private enum DayPeriod: CaseIterable {
        case morning, afternoon
    }

    private struct ScheduledItem: Identifiable {
        let work: WorkModel
        let checkIn: WorkCheckIn
        var id: UUID { checkIn.id }
    }

    private var unscheduledWorks: [WorkModel] {
        works.filter { work in
            guard work.isOpen else { return false }
            // Check if any incomplete check-in exists
            return !work.checkIns.contains(where: { ci in
                ci.status != .completed && ci.status != .skipped
            })
        }
        .sorted(by: { $0.createdAt < $1.createdAt })
    }

    private var days: [Date] {
        (0..<UIConstants.planningWindowDays).map { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
        }
    }

    private func dayID(_ day: Date) -> String {
        let start = calendar.startOfDay(for: day)
        return "day_\(Int(start.timeIntervalSince1970))"
    }

    private func dayName(for day: Date) -> String {
        let fmt = Date.FormatStyle()
            .weekday(.abbreviated)
        return day.formatted(fmt)
    }

    private func dayNumber(for day: Date) -> String {
        let fmt = Date.FormatStyle()
            .day()
        return day.formatted(fmt)
    }

    private func dayShortLabel(for day: Date) -> String {
        let fmt = Date.FormatStyle()
            .weekday(.abbreviated)
            .day()
        return day.formatted(fmt)
    }

    private func isNonSchoolDay(_ day: Date) -> Bool {
        SchoolCalendar.isNonSchoolDay(day, using: modelContext)
    }

    private func computeInitialStartDate() -> Date {
        let today = calendar.startOfDay(for: .now)
        return firstSchoolDay(onOrAfter: today)
    }

    private func firstSchoolDay(onOrAfter date: Date) -> Date {
        var d = date
        while isNonSchoolDay(d) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return d
    }

    private func movedStart(bySchoolDays days: Int) -> Date {
        var count = abs(days)
        let forward = days >= 0

        var d = startDate
        while count > 0 {
            guard let next = calendar.date(byAdding: .day, value: forward ? 1 : -1, to: d) else { break }
            d = next
            if !isNonSchoolDay(d) {
                count -= 1
            }
        }
        return d
    }

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
                startDate = Date(timeIntervalSince1970: startDateRaw)
            } else {
                startDate = computeInitialStartDate()
            }
        }
        .onChange(of: startDate) { _, new in
            startDateRaw = new.timeIntervalSince1970
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .schedule(let id):
                ScheduleCheckInSheet(workID: id, initialDate: scheduleDate, onCancel: { activeSheet = nil }, onSave: { date in
                    let service = WorkCheckInService(context: modelContext)
                    if let work = (try? modelContext.fetch(FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })))?.first {
                        _ = try? service.createCheckIn(for: work, date: date, status: .scheduled, purpose: "", note: "")
                    }
                    activeSheet = nil
                })
#if os(macOS)
                .frame(minWidth: 360)
#endif
            case .detail(let id):
                WorkDetailContainerView(workID: id) { activeSheet = nil }
#if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizing(.fitted)
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
#endif
            }
        }
    }

    private var sidebar: some View {
        InboxSidebarView(
            unscheduledWorks: unscheduledWorks,
            workTitle: { workTitle(for: $0) },
            participantNames: { participantNames(for: $0) },
            onOpen: { id in activeSheet = .detail(workID: id) },
            onSchedule: { id in
                scheduleDate = Date()
                activeSheet = .schedule(workID: id)
            }
        )
    }

    private var header: some View {
        let first = days.first ?? Date()
        let last = days.last ?? Date()
        return AgendaHeaderView(
            firstDate: first,
            lastDate: last,
            onPrev: {
                withAnimation {
                    startDate = movedStart(bySchoolDays: -UIConstants.planningNavigationStepSchoolDays)
                }
            },
            onToday: {
                withAnimation {
                    startDate = computeInitialStartDate()
                }
            },
            onNext: {
                withAnimation {
                    startDate = movedStart(bySchoolDays: UIConstants.planningNavigationStepSchoolDays)
                }
            }
        )
    }

    private var agenda: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Day strip
                DayStripView(days: days) { day in
                    withAnimation {
                        proxy.scrollTo(dayID(day), anchor: .top)
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
                                        periodCard(day: day, period: period)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            }
                            .id(dayID(day))
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .onChange(of: startDate) { _, _ in
                if let firstDay = days.first {
                    withAnimation {
                        proxy.scrollTo(dayID(firstDay), anchor: .top)
                    }
                }
            }
            .onAppear {
                if let firstDay = days.first {
                    proxy.scrollTo(dayID(firstDay), anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func dayHeader(_ day: Date) -> some View {
        HStack(spacing: 10) {
            Text(dayName(for: day))
                .font(.headline.weight(.semibold))
            Text(dayNumber(for: day))
                .font(.title2.weight(.semibold))
            Spacer()
            if isNonSchoolDay(day) {
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
        let text: String
        let color: Color
        switch period {
        case .morning:
            text = "Morning"
            color = .blue
        case .afternoon:
            text = "Afternoon"
            color = .orange
        }
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

    private func periodCard(day: Date, period: DayPeriod) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            periodChip(for: period)
            WorkDropList(
                day: day,
                period: period,
                works: works,
                isNonSchool: isNonSchoolDay(day),
                namesForWork: { work in participantNames(for: work) },
                titleForWork: workTitle(for:),
                onOpenWork: { wid in activeSheet = .detail(workID: wid) },
                onMarkCompleted: { checkIn in
                    let service = WorkCheckInService(context: modelContext)
                    do { try service.markCompleted(checkIn) } catch { }
                }
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(alignment: .center) {
            if isNonSchoolDay(day) {
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
        let isNonSchool: Bool
        let namesForWork: (WorkModel) -> String
        let titleForWork: (WorkModel) -> String
        let onOpenWork: (UUID) -> Void
        let onMarkCompleted: (WorkCheckIn) -> Void

        @State private var isTargeted: Bool = false
        @State private var insertionIndex: Int? = nil
        @State private var itemFrames: [UUID: CGRect] = [:]
        @State private var zoneSpaceID = UUID()

        private var items: [ScheduledItem] {
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            var result: [ScheduledItem] = []
            for work in works {
                for ci in work.checkIns where ci.status != .completed && ci.status != .skipped {
                    let date = ci.date
                    if date >= dayStart && date < dayEnd {
                        let hour = calendar.component(.hour, from: date)
                        switch period {
                        case .morning:
                            if hour < 12 { result.append(ScheduledItem(work: work, checkIn: ci)) }
                        case .afternoon:
                            if hour >= 12 { result.append(ScheduledItem(work: work, checkIn: ci)) }
                        }
                    }
                }
            }
            return result.sorted { $0.checkIn.date < $1.checkIn.date }
        }

        var body: some View {
            let dropDelegate = WorksCheckInDropDelegate(
                calendar: calendar,
                modelContext: modelContext,
                works: works,
                day: day,
                period: period,
                getCurrent: { items.map { $0.checkIn } },
                itemFramesProvider: { itemFrames },
                onTargetChange: { targeted in withAnimation(.easeInOut(duration: 0.15)) { isTargeted = targeted } },
                onInsertionIndexChange: { idx in if insertionIndex != idx { withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.85)) { insertionIndex = idx } } }
            )
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
                                .draggable("CHECKIN:\(item.checkIn.id.uuidString)") {
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
            .onDrop(of: [UTType.text], delegate: dropDelegate)
            .disabled(isNonSchool)
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

    private struct WorksCheckInDropDelegate: DropDelegate {
        let calendar: Calendar
        let modelContext: ModelContext
        let works: [WorkModel]
        let day: Date
        let period: DayPeriod
        let getCurrent: () -> [WorkCheckIn]
        let itemFramesProvider: () -> [UUID: CGRect]
        let onTargetChange: (Bool) -> Void
        let onInsertionIndexChange: (Int?) -> Void

        func dropEntered(info: DropInfo) {
            onTargetChange(true)
            onInsertionIndexChange(computeIndex(info))
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            onInsertionIndexChange(computeIndex(info))
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            onTargetChange(false)
            onInsertionIndexChange(nil)
        }

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [UTType.text])
        }

        func performDrop(info: DropInfo) -> Bool {
            onTargetChange(false)
            onInsertionIndexChange(nil)
            let providers = info.itemProviders(for: [UTType.text])
            guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let ns = reading as? NSString else { return }
                let payload = ns as String
                Task { @MainActor in
                    handlePayload(payload, locationY: info.location.y)
                }
            }
            return true
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

        @MainActor
        private func handlePayload(_ payload: String, locationY: CGFloat) {
            let current = getCurrent()
            let frames = itemFramesProvider()
            let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
                if let rect = frames[item.id] { return (item.id, rect) }
                return nil
            })
            let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: locationY, frames: dict)
            let baseDate = dateForSlot(day: day, period: period)

            if payload.hasPrefix("WORK:") {
                let idStr = String(payload.dropFirst("WORK:".count))
                if let wid = UUID(uuidString: idStr), let work = works.first(where: { $0.id == wid }) {
                    // Create a new check-in for this work
                    let service = WorkCheckInService(context: modelContext)
                    if let newCI = try? service.createCheckIn(for: work, date: baseDate, status: .scheduled, purpose: "", note: "") {
                        applyOrder(currentIDs: current.map { $0.id }, inserting: newCI.id, baseDate: baseDate, insertionIndex: insertionIndex)
                    }
                }
                return
            }

            if payload.hasPrefix("CHECKIN:") {
                let idStr = String(payload.dropFirst("CHECKIN:".count))
                if let cid = UUID(uuidString: idStr) {
                    // Move/reorder existing check-in
                    applyOrder(currentIDs: current.map { $0.id }, inserting: cid, baseDate: baseDate, insertionIndex: insertionIndex)
                }
                return
            }

            // Fallback: treat as raw UUID of a check-in
            if let cid = UUID(uuidString: payload.trimmingCharacters(in: .whitespacesAndNewlines)) {
                applyOrder(currentIDs: current.map { $0.id }, inserting: cid, baseDate: baseDate, insertionIndex: insertionIndex)
            }
        }

        private func computeIndex(_ info: DropInfo) -> Int {
            let current = getCurrent()
            let frames = itemFramesProvider()
            let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
                if let rect = frames[item.id] { return (item.id, rect) }
                return nil
            })
            return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
        }

        private func dateForSlot(day: Date, period: DayPeriod) -> Date {
            let startOfDay = calendar.startOfDay(for: day)
            let hour: Int = (period == .morning) ? UIConstants.morningHour : UIConstants.afternoonHour
            return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
        }
    }

    fileprivate struct WorksInboxDropDelegate: DropDelegate {
        let modelContext: ModelContext
        let onTargetChange: (Bool) -> Void

        func dropEntered(info: DropInfo) {
            onTargetChange(true)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            onTargetChange(true)
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            onTargetChange(false)
        }

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [UTType.text])
        }

        func performDrop(info: DropInfo) -> Bool {
            onTargetChange(false)
            let providers = info.itemProviders(for: [UTType.text])
            guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let ns = reading as? NSString else { return }
                let s = ns as String
                if s.hasPrefix("CHECKIN:") {
                    let idStr = String(s.dropFirst("CHECKIN:".count))
                    if let cid = UUID(uuidString: idStr) {
                        Task { @MainActor in
                            let fetch = FetchDescriptor<WorkCheckIn>(predicate: #Predicate { $0.id == cid })
                            if let ci = (try? modelContext.fetch(fetch))?.first {
                                let svc = WorkCheckInService(context: modelContext)
                                if let parent = ci.work {
                                    try? svc.delete(ci, from: parent)
                                } else {
                                    try? svc.delete(ci)
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
    }
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
                        .draggable("WORK:\(w.id.uuidString)") {
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
            .onDrop(of: [UTType.text], delegate: WorksPlanningView.WorksInboxDropDelegate(
                modelContext: modelContext,
                onTargetChange: { targeted in
                    withAnimation(.easeInOut(duration: 0.12)) { inboxIsTargeted = targeted }
                }
            ))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(inboxIsTargeted ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )
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

    private func dayShortLabel(for day: Date) -> String {
        let fmt = Date.FormatStyle()
            .weekday(.abbreviated)
            .day()
        return day.formatted(fmt)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(days, id: \.self) { day in
                    Button {
                        onTap(day)
                    } label: {
                        Text(dayShortLabel(for: day))
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

