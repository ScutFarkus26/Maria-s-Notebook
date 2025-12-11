import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WorksPlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]) private var works: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]

    @AppStorage("WorkPlanningAgenda.startDate") private var startDateRaw: Double = 0
    @AppStorage("WorksPlanningInbox.order") private var worksInboxOrderRaw: String = ""

    @State private var viewModel = WorksPlanningViewModel(
        startDate: Date(),
        calendar: Calendar.current,
        isNonSchoolDay: { _ in false },
        checkInService: { WorkCheckInService(context: $0) }
    )
    @State private var reschedulingCheckIn: WorkCheckIn? = nil
    @State private var rescheduleDate: Date = Date()

    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    
    private var absentTodayIDs: Set<UUID> {
        let today = calendar.startOfDay(for: Date())
        let descriptor = FetchDescriptor<AttendanceRecord>(predicate: #Predicate { $0.date == today })
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return Set(records.filter { $0.status == .absent }.map { $0.studentID })
    }
    
    private var unscheduledWorkIDs: [UUID] {
        viewModel.unscheduledWorks(from: works).map { $0.id }
    }

    private var orderedUnscheduledWorks: [WorkModel] {
        WorksInboxOrderStore.orderedUnscheduled(from: viewModel.unscheduledWorks(from: works), orderRaw: worksInboxOrderRaw)
    }

    private var overdueItems: [ScheduledItem] {
        let todayStart = calendar.startOfDay(for: Date())
        return works.flatMap { work -> [ScheduledItem] in
            guard work.isOpen else { return [] }
            let overdue = work.checkIns.filter { $0.status == .scheduled && $0.date < todayStart }
            return overdue.map { ScheduledItem(work: work, checkIn: $0) }
        }
        .sorted { $0.checkIn.date < $1.checkIn.date }
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
    
    private func updateInboxOrder() {
        let base: [WorkModel] = viewModel.unscheduledWorks(from: works)
        let baseIDs: [UUID] = base.map { $0.id }
        var order: [UUID] = WorksInboxOrderStore.parse(worksInboxOrderRaw).filter { baseIDs.contains($0) }
        let missing: [UUID] = base
            .filter { !order.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.id }
        order.append(contentsOf: missing)
        worksInboxOrderRaw = WorksInboxOrderStore.serialize(order)
    }
    
    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
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
        .onChange(of: unscheduledWorkIDs) { _, _ in
            updateInboxOrder()
        }
        .sheet(item: $viewModel.activeSheet) { sheet in
            activeSheetView(sheet)
        }
        .sheet(item: $reschedulingCheckIn) { checkIn in
            VStack(alignment: .leading, spacing: 16) {
                Text("Reschedule Check-In").font(.headline)
                DatePicker("Date", selection: $rescheduleDate, displayedComponents: .date)
                HStack {
                    Spacer()
                    Button("Cancel") { reschedulingCheckIn = nil }
                    Button("Save") {
                        let service = WorkCheckInService(context: modelContext)
                        do { try service.reschedule(checkIn, to: rescheduleDate) } catch { }
                        reschedulingCheckIn = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
    #if os(macOS)
            .frame(minWidth: 360)
    #endif
        }
        .alert("Error", isPresented: isErrorPresented) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    @ViewBuilder
    private func activeSheetView(_ sheet: ActiveSheet) -> some View {
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

    private var sidebar: some View {
        InboxSidebarView(
            unscheduledWorks: viewModel.unscheduledWorks(from: works),
            orderedUnscheduled: orderedUnscheduledWorks,
            workTitle: workTitle(for:),
            participantNames: participantNames(for:),
            onOpen: { id in viewModel.activeSheet = .detail(workID: id) },
            onSchedule: { id in
                viewModel.scheduleDate = Date()
                viewModel.activeSheet = .schedule(workID: id)
            },
            onUpdateOrder: { newRaw in
                worksInboxOrderRaw = newRaw
            }
            ,
            absentTodayIDs: absentTodayIDs,
            nameForStudentID: { id in
                (studentsByID[id]?.firstName.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            }
        )
    }

    private var header: some View {
        let days = viewModel.computeSchoolDays(count: 7)
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
        let days: [Date] = viewModel.computeSchoolDays(count: 7)
        let grouped: [DayKey: [ScheduledItem]] = viewModel.groupedItems(works: works)

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
                        if !overdueItems.isEmpty {
                            Section(header: overdueHeader) {
                                overdueList(items: overdueItems)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                            }
                            .id("overdue_section")
                        }
                        ForEach(days, id: \.self) { day in
                            daySection(day: day, grouped: grouped)
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
    private func daySection(day: Date, grouped: [DayKey: [ScheduledItem]]) -> some View {
        Section(header: dayHeader(day)) {
            periodsList(for: day, grouped: grouped)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func periodsList(for day: Date, grouped: [DayKey: [ScheduledItem]]) -> some View {
        let periods: [DayPeriod] = DayPeriod.allCases
        VStack(spacing: 12) {
            ForEach(periods, id: \.self) { period in
                periodCard(day: day, period: period, grouped: grouped)
            }
        }
    }

    @ViewBuilder
    private var overdueHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Overdue")
                .font(.headline.weight(.semibold))
            Spacer()
            if !overdueItems.isEmpty {
                Text("\(overdueItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
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

    @ViewBuilder
    private func overdueList(items: [ScheduledItem]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                overdueRow(for: item)
            }
        }
    }

    @ViewBuilder
    private func overdueRow(for item: ScheduledItem) -> some View {
        let (iconName, iconColor) = iconAndColor(for: item.work.workType)
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                let isToday = calendar.isDate(item.checkIn.date, inSameDayAs: Date())
                let studentIDs = item.work.participants.map { $0.studentID }
                if !studentIDs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(studentIDs.enumerated()), id: \.element) { idx, sid in
                            let raw = (studentsByID[sid]?.firstName.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
                            if !raw.isEmpty {
                                Group {
                                    if isToday && absentTodayIDs.contains(sid) {
                                        Text(raw)
                                            .font(.callout.weight(.bold))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.red, lineWidth: 1.0)
                                            )
                                    } else {
                                        Text(raw)
                                            .font(.callout.weight(.bold))
                                            .foregroundStyle(.primary)
                                    }
                                }
                                if idx < studentIDs.count - 1 {
                                    Text(",")
                                        .font(.callout.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Text(workTitle(for: item.work))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                let purpose = item.checkIn.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
                if !purpose.isEmpty {
                    Text(purpose)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(item.checkIn.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("Open Work", systemImage: "arrow.forward.circle") {
                    viewModel.activeSheet = .detail(workID: item.work.id)
                }
                Button("Mark Completed", systemImage: "checkmark.circle") {
                    viewModel.markCompleted(item.checkIn, context: modelContext)
                }
                Button("Reschedule", systemImage: "calendar") {
                    rescheduleDate = item.checkIn.date
                    reschedulingCheckIn = item.checkIn
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.activeSheet = .detail(workID: item.work.id)
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

    private func iconAndColor(for type: WorkModel.WorkType) -> (String, Color) {
        switch type {
        case .research: return ("magnifyingglass", .teal)
        case .followUp: return ("bolt.fill", .orange)
        case .practice: return ("arrow.triangle.2.circlepath", .purple)
        }
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
                namesForWork: participantNames(for:),
                titleForWork: workTitle(for:),
                onOpenWork: { id in
                    viewModel.activeSheet = .detail(workID: id)
                },
                onMarkCompleted: { ci in
                    ci.status = .completed
                    try? modelContext.save()
                },
                absentTodayIDs: absentTodayIDs,
                nameForStudentID: { id in
                    (studentsByID[id]?.firstName.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
                }
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
        let onOpenWork: (UUID) -> Void
        let onMarkCompleted: (WorkCheckIn) -> Void

        let absentTodayIDs: Set<UUID>
        let nameForStudentID: (UUID) -> String

        @State private var isTargeted: Bool = false
        @State private var insertionIndex: Int? = nil
        @State private var itemFrames: [UUID: CGRect] = [:]
        @State private var zoneSpaceID = UUID()

        // Current items for this day/period slot
        private var currentItemsForSlot: [ScheduledItem] {
            let key = DayKey(dayStart: calendar.startOfDay(for: day), period: period)
            return grouped[key] ?? []
        }

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
                        let framesUnsorted: [(UUID, CGRect)] = items.compactMap { it in
                            if let rect = itemFrames[it.checkIn.id] {
                                return (it.checkIn.id, rect)
                            }
                            return nil
                        }
                        let frames: [(UUID, CGRect)] = framesUnsorted.sorted { (lhs, rhs) in
                            lhs.1.minY < rhs.1.minY
                        }

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
            .onDrop(of: [.plainText], delegate: WorkAgendaDropDelegate(
                calendar: calendar,
                modelContext: modelContext,
                works: works,
                day: day,
                period: period,
                getCurrent: { currentItemsForSlot },
                itemFramesProvider: { itemFrames },
                onTargetChange: { targeted in
                    isTargeted = targeted
                    if !targeted { insertionIndex = nil }
                },
                onInsertionIndexChange: { idx in
                    if insertionIndex != idx { insertionIndex = idx }
                }
            ))
            .disabled(isNonSchool)
        }

        private func iconAndColor(for type: WorkModel.WorkType) -> (String, Color) {
            switch type {
            case .research: return ("magnifyingglass", .teal)
            case .followUp: return ("bolt.fill", .orange)
            case .practice: return ("arrow.triangle.2.circlepath", .purple)
            }
        }

        @ViewBuilder
        private func rowView(for item: ScheduledItem) -> some View {
            let (iconName, iconColor) = iconAndColor(for: item.work.workType)
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    let isTodaySlot = calendar.isDate(day, inSameDayAs: Date())
                    let studentIDs = item.work.participants.map { $0.studentID }
                    if !studentIDs.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(studentIDs.enumerated()), id: \.element) { idx, sid in
                                let raw = nameForStudentID(sid).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !raw.isEmpty {
                                    Group {
                                        if isTodaySlot && absentTodayIDs.contains(sid) {
                                            Text(raw)
                                                .font(.callout.weight(.bold))
                                                .foregroundStyle(.primary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.red, lineWidth: 1.0)
                                                )
                                        } else {
                                            Text(raw)
                                                .font(.callout.weight(.bold))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    if idx < studentIDs.count - 1 {
                                        Text(",")
                                            .font(.callout.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Text(titleForWork(item.work))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    let purpose = item.checkIn.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !purpose.isEmpty {
                        Text(purpose)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
            .contentShape(Rectangle())
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

struct WorkAgendaDropDelegate: DropDelegate {
    let calendar: Calendar
    let modelContext: ModelContext
    let works: [WorkModel]
    let day: Date
    let period: DayPeriod
    let getCurrent: () -> [ScheduledItem]
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
        info.hasItemsConforming(to: [.plainText])
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetChange(false)
        onInsertionIndexChange(nil)
        let providers = info.itemProviders(for: [.plainText])
        return performDropFromProvidersAsync(providers: providers, location: info.location)
    }

    private func performDropFromProvidersAsync(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }

        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let s = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)

            let payload: PlanningDragItem?
            if s.hasPrefix("WORK:"), let id = UUID(uuidString: String(s.dropFirst("WORK:".count))) {
                payload = .work(id)
            } else if s.hasPrefix("CHECKIN:"), let id = UUID(uuidString: String(s.dropFirst("CHECKIN:".count))) {
                payload = .checkIn(id)
            } else if let id = UUID(uuidString: s) {
                payload = .checkIn(id)
            } else {
                payload = nil
            }

            if let payload {
                Task { @MainActor in
                    handleTypedPayload(payload, locationY: location.y)
                }
            }
        }
        return true
    }

    @MainActor
    private func handleTypedPayload(_ payload: PlanningDragItem, locationY: CGFloat) {
        let current = getCurrent()
        let frames = itemFramesProvider()
        let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
            if let rect = frames[item.checkIn.id] { return (item.checkIn.id, rect) }
            return nil
        })
        let idx = PlanningDropUtils.computeInsertionIndex(locationY: locationY, frames: dict)
        let baseDate = dateForSlot(day: day, period: period)

        switch payload.kind {
        case .work:
            if let work = works.first(where: { $0.id == payload.id }) {
                let service = WorkCheckInService(context: modelContext)
                if let newCI = try? service.createCheckIn(for: work, date: baseDate, status: .scheduled, purpose: "", note: "") {
                    applyOrder(currentIDs: current.map { $0.checkIn.id }, inserting: newCI.id, baseDate: baseDate, insertionIndex: idx)
                }
            }
        case .checkIn:
            applyOrder(currentIDs: current.map { $0.checkIn.id }, inserting: payload.id, baseDate: baseDate, insertionIndex: idx)
        }
    }

    @MainActor
    private func applyOrder(currentIDs: [UUID], inserting id: UUID, baseDate: Date, insertionIndex: Int) {
        var ids = currentIDs
        ids.removeAll(where: { $0 == id })
        let bounded = max(0, min(insertionIndex, ids.count))
        ids.insert(id, at: bounded)
        let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: UIConstants.scheduleSpacingSeconds)
        let allCIs = works.flatMap { $0.checkIns }
        for cid in ids {
            if let target = allCIs.first(where: { $0.id == cid }) {
                target.date = timeMap[cid] ?? target.date
                target.status = .scheduled
            }
        }
        try? modelContext.save()
    }

    private func dateForSlot(day: Date, period: DayPeriod) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: period.baseHour, to: startOfDay) ?? startOfDay
    }

    private func computeIndex(_ info: DropInfo) -> Int? {
        let current = getCurrent()
        let frames = itemFramesProvider()
        let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
            if let rect = frames[item.checkIn.id] { return (item.checkIn.id, rect) }
            return nil
        })
        return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
    }
}

// MARK: - Subviews

private struct InboxSidebarView: View {
    let unscheduledWorks: [WorkModel]
    let orderedUnscheduled: [WorkModel]
    let workTitle: (WorkModel) -> String
    let participantNames: (WorkModel) -> String
    let onOpen: (UUID) -> Void
    let onSchedule: (UUID) -> Void
    let onUpdateOrder: (String) -> Void
    let absentTodayIDs: Set<UUID>
    let nameForStudentID: (UUID) -> String

    @State private var inboxIsTargeted: Bool = false
    @State private var insertionIndex: Int? = nil
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var spaceID = UUID()

    @Environment(\.modelContext) private var modelContext

    private func iconAndColor(for type: WorkModel.WorkType) -> (String, Color) {
        switch type {
        case .research: return ("magnifyingglass", .teal)
        case .followUp: return ("bolt.fill", .orange)
        case .practice: return ("arrow.triangle.2.circlepath", .purple)
        }
    }

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
                    ForEach(orderedUnscheduled, id: \.id) { w in
                        Button {
                            onOpen(w.id)
                        } label: {
                            inboxRowContent(w, includeMenu: true)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                        .draggable(PlanningDragItem.work(w.id)) {
                            inboxRowContent(w, includeMenu: false)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
                        }
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: WorkInboxPillFramePreference.self,
                                    value: [w.id: proxy.frame(in: .named(spaceID))]
                                )
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
            }
            .coordinateSpace(name: spaceID)
            .onPreferenceChange(WorkInboxPillFramePreference.self) { frames in
                itemFrames = frames
            }
            .onDrop(of: [.plainText], delegate: WorksInboxDropDelegate(
                modelContext: modelContext,
                orderedUnscheduled: orderedUnscheduled,
                getCurrentIDs: { orderedUnscheduled.map { $0.id } },
                itemFramesProvider: { itemFrames },
                onTargetChange: { over in
                    inboxIsTargeted = over
                    if !over { insertionIndex = nil }
                },
                onInsertionIndexChange: { idx in
                    insertionIndex = idx
                },
                onUpdateOrder: { newRaw in
                    onUpdateOrder(newRaw)
                }
            ))
            .overlay(
                GeometryReader { proxy in
                    if let idx = insertionIndex {
                        let framesUnsorted: [(UUID, CGRect)] = orderedUnscheduled.compactMap { w in
                            if let rect = itemFrames[w.id] { return (w.id, rect) }
                            return nil
                        }
                        let frames: [(UUID, CGRect)] = framesUnsorted.sorted { lhs, rhs in lhs.1.minY < rhs.1.minY }
                        if frames.isEmpty {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 28, height: 3)
                                .position(x: proxy.size.width / 2, y: 12)
                        } else {
                            let y: CGFloat = (idx < frames.count) ? frames[idx].1.minY : (frames.last!.1.maxY + 8)
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 28, height: 3)
                                .position(x: proxy.size.width / 2, y: y)
                        }
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(inboxIsTargeted ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )
            .animation(.easeInOut(duration: 0.15), value: inboxIsTargeted)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private func inboxRowContent(_ w: WorkModel, includeMenu: Bool) -> some View {
        HStack(spacing: 10) {
            let (iconName, iconColor) = iconAndColor(for: w.workType)
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                let studentIDs = w.participants.map { $0.studentID }
                if !studentIDs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(studentIDs.enumerated()), id: \.element) { idx, sid in
                            let raw = nameForStudentID(sid).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !raw.isEmpty {
                                Group {
                                    if absentTodayIDs.contains(sid) {
                                        Text(raw)
                                            .font(.callout.weight(.bold))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.red, lineWidth: 1.0)
                                            )
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .allowsTightening(true)
                                    } else {
                                        Text(raw)
                                            .font(.callout.weight(.bold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .allowsTightening(true)
                                    }
                                }
                                if idx < studentIDs.count - 1 {
                                    Text(",")
                                        .font(.callout.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .clipped()
                }
                Text(workTitle(w))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                let purpose = w.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !purpose.isEmpty {
                    Text(purpose)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if includeMenu {
                Menu {
                    Button("Open", systemImage: "arrow.forward.circle") { onOpen(w.id) }
                    Button("Schedule Check-In", systemImage: "calendar.badge.plus") {
                        onSchedule(w.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Drop handling helpers

    private func handleInboxDrop(items: [PlanningDragItem], location: CGPoint) -> Bool {
        guard let item = items.first else { return false }
        switch item.kind {
        case .checkIn:
            Task { @MainActor in
                await handleCheckInDropToInbox(id: item.id)
            }
            return true
        case .work:
            handleWorkReorderDrop(itemID: item.id, locationY: location.y)
            return true
        }
    }

    private func handleInboxDropStrings(items: [String], location: CGPoint) -> Bool {
        guard let raw = items.first?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return false }
        if raw.hasPrefix("CHECKIN:"), let id = UUID(uuidString: String(raw.dropFirst(8))) {
            Task { @MainActor in
                await handleCheckInDropToInbox(id: id)
            }
            return true
        }
        if raw.hasPrefix("WORK:"), let id = UUID(uuidString: String(raw.dropFirst(5))) {
            handleWorkReorderDrop(itemID: id, locationY: location.y)
            return true
        }
        // Fallback: plain UUID → treat as check-in
        if let id = UUID(uuidString: raw) {
            Task { @MainActor in
                await handleCheckInDropToInbox(id: id)
            }
            return true
        }
        return false
    }

    @MainActor
    private func handleCheckInDropToInbox(id: UUID) async {
        let fetch = FetchDescriptor<WorkCheckIn>(predicate: #Predicate { $0.id == id })
        if let ci = (try? modelContext.fetch(fetch))?.first {
            let svc = WorkCheckInService(context: modelContext)
            if let parent = ci.work {
                try? svc.delete(ci, from: parent)
            } else {
                try? svc.delete(ci)
            }
        }
    }

    private func handleWorkReorderDrop(itemID: UUID, locationY: CGFloat) {
        let currentIDs: [UUID] = orderedUnscheduled.map { $0.id }
        var framesByID: [UUID: CGRect] = [:]
        for id in currentIDs {
            if let f = itemFrames[id] {
                framesByID[id] = f
            }
        }
        let idx: Int = PlanningDropUtils.computeInsertionIndex(locationY: locationY, frames: framesByID)
        var newIDs: [UUID] = currentIDs
        newIDs.removeAll(where: { $0 == itemID })
        let bounded: Int = max(0, min(idx, newIDs.count))
        newIDs.insert(itemID, at: bounded)
        onUpdateOrder(WorksInboxOrderStore.serialize(newIDs))
    }
}

fileprivate struct WorkInboxPillFramePreference: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
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
    let schema = Schema([
        Item.self,
        Student.self,
        Lesson.self,
        StudentLesson.self,
        WorkModel.self,
        WorkParticipantEntity.self,
        WorkCompletionRecord.self,
        AttendanceRecord.self,
        WorkCheckIn.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    return WorksPlanningView()
        .modelContainer(container)
}

// New drop delegate for inbox reordering and dropping
struct WorksInboxDropDelegate: DropDelegate {
    let modelContext: ModelContext
    let orderedUnscheduled: [WorkModel]
    let getCurrentIDs: () -> [UUID]
    let itemFramesProvider: () -> [UUID: CGRect]
    let onTargetChange: (Bool) -> Void
    let onInsertionIndexChange: (Int?) -> Void
    let onUpdateOrder: (String) -> Void

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
        info.hasItemsConforming(to: [.plainText])
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetChange(false)
        onInsertionIndexChange(nil)
        let providers = info.itemProviders(for: [.plainText])
        return performDropFromProvidersAsync(providers: providers, location: info.location)
    }

    private func performDropFromProvidersAsync(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let raw = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)

            if raw.hasPrefix("CHECKIN:"), let id = UUID(uuidString: String(raw.dropFirst(8))) {
                Task { @MainActor in
                    await handleCheckInDropToInbox(id: id)
                }
                return
            }
            if raw.hasPrefix("WORK:"), let id = UUID(uuidString: String(raw.dropFirst(5))) {
                handleWorkReorderDrop(itemID: id, locationY: location.y)
                return
            }
            // Fallback: plain UUID → treat as check-in
            if let id = UUID(uuidString: raw) {
                Task { @MainActor in
                    await handleCheckInDropToInbox(id: id)
                }
                return
            }
        }
        return true
    }

    private func computeIndex(_ info: DropInfo) -> Int? {
        let currentIDs = getCurrentIDs()
        var framesByID: [UUID: CGRect] = [:]
        let frames = itemFramesProvider()
        for id in currentIDs {
            if let f = frames[id] { framesByID[id] = f }
        }
        return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: framesByID)
    }

    private func handleWorkReorderDrop(itemID: UUID, locationY: CGFloat) {
        let currentIDs = getCurrentIDs()
        var framesByID: [UUID: CGRect] = [:]
        let frames = itemFramesProvider()
        for id in currentIDs { if let f = frames[id] { framesByID[id] = f } }
        let idx: Int = PlanningDropUtils.computeInsertionIndex(locationY: locationY, frames: framesByID)
        var newIDs: [UUID] = currentIDs
        newIDs.removeAll(where: { $0 == itemID })
        let bounded: Int = max(0, min(idx, newIDs.count))
        newIDs.insert(itemID, at: bounded)
        onUpdateOrder(WorksInboxOrderStore.serialize(newIDs))
    }

    @MainActor
    private func handleCheckInDropToInbox(id: UUID) async {
        let fetch = FetchDescriptor<WorkCheckIn>(predicate: #Predicate { $0.id == id })
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

