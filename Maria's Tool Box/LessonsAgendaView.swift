import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LessonsAgendaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @Query private var contracts: [WorkContract]

    @AppStorage("PlanningInbox.order") private var inboxOrderRaw: String = ""
    @AppStorage("LessonsAgenda.startDate") private var startDateRaw: Double = 0

    @AppStorage("LessonsAgenda.missWindow") private var missWindowRaw: String = MissWindow.all.rawValue
    @AppStorage("Planning.recentWindowDays") private var recentWindowDays: Int = 1

    private enum MissWindow: String, CaseIterable {
        case all, d1, d2, d3
        var threshold: Int? {
            switch self {
            case .all: return nil
            case .d1: return 1
            case .d2: return 2
            case .d3: return 3
            }
        }
        var label: String {
            switch self {
            case .all: return "All"
            case .d1: return "Today"
            case .d2: return "2d"
            case .d3: return "3d"
            }
        }
    }

    private var missWindow: MissWindow { MissWindow(rawValue: missWindowRaw) ?? .all }

    private func syncRecentWindowWithMissWindow() {
        switch missWindow {
        case .all: recentWindowDays = 0
        case .d1: recentWindowDays = 1
        case .d2: recentWindowDays = 2
        case .d3: recentWindowDays = 3
        }
    }

    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @State private var startDate: Date = Date()
    @State private var selectedStudentLessonForDetail: StudentLesson? = nil
    @State private var isInboxTargeted: Bool = false

    // Age settings
    @AppStorage("LessonAge.warningDays") private var ageWarningDays: Int = LessonAgeDefaults.warningDays
    @AppStorage("LessonAge.overdueDays") private var ageOverdueDays: Int = LessonAgeDefaults.overdueDays
    @AppStorage("LessonAge.freshColorHex") private var ageFreshHex: String = LessonAgeDefaults.freshColorHex
    @AppStorage("LessonAge.warningColorHex") private var ageWarningHex: String = LessonAgeDefaults.warningColorHex
    @AppStorage("LessonAge.overdueColorHex") private var ageOverdueHex: String = LessonAgeDefaults.overdueColorHex

    // MARK: - Blocking Logic

    /// Returns true if this lesson is "blocked" by incomplete work from the PREVIOUS lesson in the sequence
    private func isBlocked(_ sl: StudentLesson) -> Bool {
        // 1. Resolve current lesson details (Robust fallback if relationship is nil)
        guard let currentLesson = sl.lesson ?? lessons.first(where: { $0.id == sl.lessonID }) else {
            return false
        }
        
        // Helper for fuzzy matching
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        
        // 2. Find the previous lesson in this group/sequence using fuzzy matching
        let subjectKey = norm(currentLesson.subject)
        let groupKey = norm(currentLesson.group)
        
        // Find all lessons in this group
        let groupLessons = lessons.filter {
            norm($0.subject) == subjectKey && norm($0.group) == groupKey
        }.sorted { $0.orderInGroup < $1.orderInGroup }
        
        guard let currentIndex = groupLessons.firstIndex(where: { $0.id == currentLesson.id }),
              currentIndex > 0 else {
            // No previous lesson, so it can't be blocked
            return false
        }
        
        let previousLesson = groupLessons[currentIndex - 1]
        
        // 3. Check if ANY student in this StudentLesson has incomplete work (Active/Review contract) for the previous lesson
        for studentID in sl.studentIDs {
            let sidString = studentID.uuidString
            let pidString = previousLesson.id.uuidString
            
            // Check for contracts that are NOT complete
            // We look for .active or .review status
            let hasIncompleteWork = contracts.contains { c in
                c.studentID == sidString &&
                c.lessonID == pidString &&
                (c.status == .active || c.status == .review)
            }
            
            if hasIncompleteWork {
                return true
            }
        }
        
        return false
    }

    private var allUnscheduled: [StudentLesson] {
        studentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }
    }
    
    // Lessons ready to be presented (not blocked)
    private var readyLessons: [StudentLesson] {
        let base = allUnscheduled.filter { !isBlocked($0) }
        return InboxOrderStore.orderedUnscheduled(from: base, orderRaw: inboxOrderRaw)
            .filter { anyStudentMeetsMissWindow($0) }
    }
    
    // Lessons blocked by previous work
    private var blockedLessons: [StudentLesson] {
        return allUnscheduled.filter { isBlocked($0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func anyStudentMeetsMissWindow(_ sl: StudentLesson) -> Bool {
        guard let threshold = missWindow.threshold else { return true }
        for sid in sl.resolvedStudentIDs {
            let days = daysSinceLastLessonByStudent[sid] ?? Int.max
            if days >= threshold { return true }
        }
        return false
    }

    private var visibleStudents: [Student] {
        TestStudentsFilter.filterVisible(students, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    private func isNonSchool(_ day: Date) -> Bool {
        SchoolCalendar.isNonSchoolDay(day, using: modelContext)
    }

    private var days: [Date] {
        // Compute 14 upcoming school days starting at startDate
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: startDate)
        var safety = 0
        while result.count < 14 && safety < 1000 {
            if !isNonSchool(cursor) { result.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            safety += 1
        }
        return result
    }

    private var daysSinceLastLessonByStudent: [UUID: Int] {
        var result: [UUID: Int] = [:]

        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let excludedLessonIDs: Set<UUID> = {
            let ids = lessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id }
            return Set(ids)
        }()

        let given = studentLessons.filter { $0.isGiven && !excludedLessonIDs.contains($0.resolvedLessonID) }

        var lastDateByStudent: [UUID: Date] = [:]
        for sl in given {
            let when = sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
            for sid in sl.resolvedStudentIDs {
                if let existing = lastDateByStudent[sid] {
                    if when > existing { lastDateByStudent[sid] = when }
                } else {
                    lastDateByStudent[sid] = when
                }
            }
        }

        for s in students {
            if let last = lastDateByStudent[s.id] {
                let days = LessonAgeHelper.schoolDaysSinceCreation(
                    createdAt: last,
                    asOf: Date(),
                    using: modelContext,
                    calendar: calendar
                )
                result[s.id] = days
            } else {
                result[s.id] = Int.max
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // Top: Inbox (~50% height)
                inboxView
                    .frame(height: proxy.size.height * 0.5)
                Divider()
                // Bottom: Calendar strip (~50% height)
                calendarStrip
                    .frame(height: proxy.size.height * 0.5)
            }
        }
        .onAppear {
            if startDateRaw != 0 {
                startDate = Date(timeIntervalSinceReferenceDate: startDateRaw)
            } else {
                startDate = AgendaSchoolDayRules.computeInitialStartDate(
                    calendar: calendar,
                    isNonSchoolDay: { day in SchoolCalendar.isNonSchoolDay(day, using: modelContext) }
                )
                startDateRaw = startDate.timeIntervalSinceReferenceDate
            }
            syncInboxOrderWithCurrentBase()
            syncRecentWindowWithMissWindow()
        }
        .onChange(of: startDate) { _, new in
            startDateRaw = new.timeIntervalSinceReferenceDate
        }
        .onChange(of: studentLessons.map { $0.id }) { _, _ in
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: missWindowRaw) { _, _ in
            syncRecentWindowWithMissWindow()
        }
        .sheet(item: $selectedStudentLessonForDetail) { sl in
            StudentLessonDetailView(studentLesson: sl) {
                selectedStudentLessonForDetail = nil
            }
        #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
        #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
        }
    }

    // MARK: - Inbox
    private var inboxView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                Text("Presentations Inbox")
                    .font(.headline)
                Spacer()
                
                Picker("Missed", selection: Binding(
                    get: { missWindow },
                    set: { missWindowRaw = $0.rawValue }
                )) {
                    ForEach(MissWindow.allCases, id: \.self) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Text("\(readyLessons.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // 1. BLOCKED / WAITING SECTION
                    if !blockedLessons.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("On Deck (Waiting for Work)", systemImage: "hourglass")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(blockedLessons, id: \.id) { sl in
                                        inboxRow(sl)
                                            .opacity(0.6)
                                            .saturation(0.5)
                                            .overlay(alignment: .topTrailing) {
                                                Image(systemName: "lock.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .padding(6)
                                            }
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.top, 12)
                    }

                    // 2. READY SECTION
                    if readyLessons.isEmpty {
                        if blockedLessons.isEmpty {
                            ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle", description: Text("No unscheduled presentations."))
                                .padding(.top, 40)
                        } else {
                            Text("All planned presentations are waiting on work.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 20)
                        }
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], alignment: .leading, spacing: 8) {
                            ForEach(readyLessons, id: \.id) { sl in
                                inboxRow(sl)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .overlay {
            if isInboxTargeted {
                Color.accentColor.opacity(0.15)
                    .allowsHitTesting(false)
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
                
                VStack {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop to Unschedule")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.text], delegate: InboxDropDelegate(
            modelContext: modelContext,
            studentLessons: studentLessons,
            isTargeted: $isInboxTargeted
        ))
    }

    @ViewBuilder
    private func inboxRow(_ sl: StudentLesson) -> some View {
        HStack(spacing: 0) {
            StudentLessonPill(
                snapshot: filteredSnapshot(sl),
                day: Date(),
                targetStudentLessonID: sl.id,
                enableMissHighlight: true
            )
            .onTapGesture { selectedStudentLessonForDetail = sl }
            .onDrag {
                let provider = NSItemProvider(object: NSString(string: sl.id.uuidString))
                provider.suggestedName = sl.lesson?.name ?? "Lesson"
                return provider
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Calendar Strip
    private var calendarStrip: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button { moveStart(bySchoolDays: -UIConstants.planningNavigationStepSchoolDays) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                    Spacer()
                    Button("Today") {
                        let targetDate = AgendaSchoolDayRules.computeInitialStartDate(calendar: calendar, isNonSchoolDay: { isNonSchool($0) })
                        
                        // If we are already grounded on the correct start date, just scroll to it.
                        // Otherwise, update startDate, which will trigger the onChange below.
                        if calendar.isDate(targetDate, inSameDayAs: startDate) {
                            if let first = days.first {
                                withAnimation {
                                    proxy.scrollTo(first, anchor: .leading)
                                }
                            }
                        } else {
                            startDate = targetDate
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { moveStart(bySchoolDays: UIConstants.planningNavigationStepSchoolDays) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(days, id: \.self) { day in
                            BetaDayColumn(day: day, allStudentLessons: studentLessons, onClear: { sl in
                                sl.scheduledFor = nil
                                try? modelContext.save()
                            }, onSelect: { sl in
                                selectedStudentLessonForDetail = sl
                            })
                            .id(day)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .onChange(of: startDate) { _, _ in
                if let first = days.first {
                    withAnimation {
                        proxy.scrollTo(first, anchor: .leading)
                    }
                }
            }
        }
    }

    private func moveStart(bySchoolDays delta: Int) {
        guard delta != 0 else { return }
        var remaining = abs(delta)
        var cursor = calendar.startOfDay(for: startDate)
        let step = delta > 0 ? 1 : -1
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if !isNonSchool(cursor) { remaining -= 1 }
        }
        startDate = cursor
    }

    // MARK: - Helpers
    private func syncInboxOrderWithCurrentBase() {
        let base = studentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }
        let baseIDs = base.map { $0.id }
        var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
        let missing = base
            .filter { !order.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.id }
        order.append(contentsOf: missing)
        inboxOrderRaw = InboxOrderStore.serialize(order)
    }

    private func ageColor(for sl: StudentLesson) -> Color {
        if sl.isGiven { return .clear }
        let fresh = ColorUtils.color(from: ageFreshHex)
        let warn = ColorUtils.color(from: ageWarningHex)
        let overdue = ColorUtils.color(from: ageOverdueHex)
        let base = sl.givenAt ?? sl.createdAt
        let days = schoolDaysBetween(from: base, to: Date())
        if days >= ageOverdueDays { return overdue }
        if days >= ageWarningDays { return warn }
        return fresh
    }

    private func schoolDaysBetween(from start: Date, to end: Date) -> Int {
        var count = 0
        var d = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while d < endDay {
            if !SchoolCalendar.isNonSchoolDay(d, using: modelContext) { count += 1 }
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return count
    }

    private func filteredSnapshot(_ sl: StudentLesson) -> StudentLessonSnapshot {
        let snap = sl.snapshot()
        let hiddenIDs = TestStudentsFilter.hiddenIDs(from: students, show: showTestStudents, namesRaw: testStudentNamesRaw)
        let visibleIDs = snap.studentIDs.filter { !hiddenIDs.contains($0) }
        return StudentLessonSnapshot(
            id: snap.id,
            lessonID: snap.lessonID,
            studentIDs: visibleIDs,
            createdAt: snap.createdAt,
            scheduledFor: snap.scheduledFor,
            givenAt: snap.givenAt,
            isPresented: snap.isPresented,
            notes: snap.notes,
            needsPractice: snap.needsPractice,
            needsAnotherPresentation: snap.needsAnotherPresentation,
            followUpWork: snap.followUpWork
        )
    }

    // MARK: - Nested Day Column
    private struct BetaDayColumn: View {
        @Environment(\.modelContext) private var modelContext
        @Environment(\.calendar) private var calendar

        let day: Date
        let allStudentLessons: [StudentLesson]
        let onClear: (StudentLesson) -> Void
        let onSelect: (StudentLesson) -> Void

        @State private var itemFrames: [UUID: CGRect] = [:]
        @State private var zoneSpaceID = UUID()
        @State private var isTargeted: Bool = false
        @State private var insertionIndex: Int? = nil

        private var scheduledLessonsForDay: [StudentLesson] {
            allStudentLessons.filter { sl in
                guard let scheduled = sl.scheduledFor, !sl.isGiven else { return false }
                return calendar.isDate(scheduled, inSameDayAs: day)
            }
            .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Day header
                HStack(spacing: 6) {
                    Text(day.formatted(Date.FormatStyle().weekday(.abbreviated)))
                        .font(.caption.weight(.semibold))
                    Text(day.formatted(Date.FormatStyle().day()))
                        .font(.headline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 6)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(isTargeted ? 0.08 : 0.04))
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 2)
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            if scheduledLessonsForDay.isEmpty {
                                Text("No plans yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                            } else {
                                ForEach(scheduledLessonsForDay, id: \.id) { sl in
                                    StudentLessonPill(snapshot: sl.snapshot(), day: day, targetStudentLessonID: sl.id, showTimeBadge: false)
                                        .onTapGesture { onSelect(sl) }
                                        .draggable(sl.id.uuidString) {
                                            StudentLessonPill(snapshot: sl.snapshot(), day: day, targetStudentLessonID: sl.id, showTimeBadge: false).opacity(0.85)
                                        }
                                        .contextMenu {
                                            Button("Clear Schedule", systemImage: "xmark.circle") {
                                                onClear(sl)
                                            }
                                        }
                                        .background(
                                            GeometryReader { proxy in
                                                Color.clear.preference(
                                                    key: PillFramePreference.self,
                                                    value: [sl.id: proxy.frame(in: .named(zoneSpaceID))]
                                                )
                                            }
                                        )
                                }
                            }
                        }
                        .padding(8)
                    }
                }
                .coordinateSpace(name: zoneSpaceID)
                .onPreferenceChange(PillFramePreference.self) { frames in
                    itemFrames = frames
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onDrop(of: [UTType.text], delegate: DayColumnDropDelegate(
                    calendar: calendar,
                    modelContext: modelContext,
                    allStudentLessons: allStudentLessons,
                    day: day,
                    getCurrent: { scheduledLessonsForDay },
                    itemFramesProvider: { itemFrames },
                    onTargetChange: { targeted in
                        withAnimation(.easeInOut(duration: 0.12)) { isTargeted = targeted }
                    },
                    onInsertionIndexChange: { idx in
                        if insertionIndex != idx {
                            withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.85)) { insertionIndex = idx }
                        }
                    }
                ))
                .frame(width: 360)
                .frame(maxHeight: .infinity)
            }
        }

        private struct PillFramePreference: PreferenceKey {
            static var defaultValue: [UUID: CGRect] = [:]
            static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
                value.merge(nextValue(), uniquingKeysWith: { $1 })
            }
        }
    }
    
    // MARK: - Drop Delegate for Inbox
    private struct InboxDropDelegate: DropDelegate {
        let modelContext: ModelContext
        let studentLessons: [StudentLesson]
        @Binding var isTargeted: Bool
        
        func dropEntered(info: DropInfo) {
            withAnimation { isTargeted = true }
        }
        
        func dropExited(info: DropInfo) {
            withAnimation { isTargeted = false }
        }
        
        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.text])
        }
        
        func performDrop(info: DropInfo) -> Bool {
            withAnimation { isTargeted = false }
            let providers = info.itemProviders(for: [.text])
            guard let provider = providers.first else { return false }
            
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let str = reading as? String, let id = UUID(uuidString: str) else { return }
                
                Task { @MainActor in
                    if let sl = studentLessons.first(where: { $0.id == id }) {
                        // Only process if it actually has a schedule to clear
                        if sl.scheduledFor != nil {
                            sl.scheduledFor = nil
                            try? modelContext.save()
                        }
                    }
                }
            }
            return true
        }
    }

    // MARK: - Drop Delegate for day column
    private struct DayColumnDropDelegate: DropDelegate {
        let calendar: Calendar
        let modelContext: ModelContext
        let allStudentLessons: [StudentLesson]
        let day: Date
        let getCurrent: () -> [StudentLesson]
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
            return performDropFromProvidersAsync(providers: providers, location: info.location)
        }

        private func computeIndex(_ info: DropInfo) -> Int? {
            let current = getCurrent()
            let frames = itemFramesProvider()
            let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
                if let rect = frames[item.id] { return (item.id, rect) }
                return nil
            })
            return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
        }

        private func performDropFromProvidersAsync(providers: [NSItemProvider], location: CGPoint) -> Bool {
            guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let ns = reading as? NSString else { return }
                let payload = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = UUID(uuidString: payload) {
                    Task { @MainActor in
                        applyDrop(of: id, locationY: location.y)
                    }
                }
            }
            return true
        }

        @MainActor
        private func applyDrop(of id: UUID, locationY: CGFloat) {
            let current = getCurrent()
            var ids = current.map { $0.id }
            if let existing = ids.firstIndex(of: id) { ids.remove(at: existing) }
            let frames = itemFramesProvider()
            let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
                if let rect = frames[item.id] { return (item.id, rect) }
                return nil
            })
            let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: locationY, frames: dict)
            let bounded = max(0, min(insertionIndex, ids.count))
            ids.insert(id, at: bounded)
            let baseDate = baseDateForDay(day: day, calendar: calendar)
            let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1)
            for id in ids {
                if let item = allStudentLessons.first(where: { $0.id == id }) {
                    item.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                }
            }
            try? modelContext.save()
        }

        private func baseDateForDay(day: Date, calendar: Calendar) -> Date {
            let startOfDay = calendar.startOfDay(for: day)
            return calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay
        }
    }
}
