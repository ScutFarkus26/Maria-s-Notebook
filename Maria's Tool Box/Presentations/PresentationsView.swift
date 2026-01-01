import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum PresentationsMissWindow: String, CaseIterable {
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

struct PresentationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @Query private var contracts: [WorkContract]

    @AppStorage("PlanningInbox.order") private var inboxOrderRaw: String = ""
    @AppStorage("LessonsAgenda.startDate") private var startDateRaw: Double = 0

    @AppStorage("LessonsAgenda.missWindow") private var missWindowRaw: String = PresentationsMissWindow.all.rawValue
    @AppStorage("Planning.recentWindowDays") private var recentWindowDays: Int = 1

    private var missWindow: PresentationsMissWindow { PresentationsMissWindow(rawValue: missWindowRaw) ?? .all }

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

    /// Returns a map of StudentID -> Blocking WorkContract for the previous lesson
    private func getBlockingContracts(_ sl: StudentLesson) -> [UUID: WorkContract] {
        // 1. Resolve current lesson details (Robust fallback if relationship is nil)
        guard let currentLesson = sl.lesson ?? lessons.first(where: { $0.id == sl.lessonID }) else {
            return [:]
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
            return [:]
        }
        
        let previousLesson = groupLessons[currentIndex - 1]
        
        // 3. Check if ANY student in this StudentLesson has incomplete work (Active/Review contract) for the previous lesson
        var blocking: [UUID: WorkContract] = [:]
        
        for studentID in sl.studentIDs {
            let sidString = studentID.uuidString
            let pidString = previousLesson.id.uuidString
            
            // Check for contracts that are NOT complete
            // We look for .active or .review status
            if let contract = contracts.first(where: { c in
                c.studentID == sidString &&
                c.lessonID == pidString &&
                (c.status == .active || c.status == .review)
            }) {
                blocking[studentID] = contract
            }
        }
        
        return blocking
    }

    /// Returns true if this lesson is "blocked" by incomplete work from the PREVIOUS lesson in the sequence
    private func isBlocked(_ sl: StudentLesson) -> Bool {
        !getBlockingContracts(sl).isEmpty
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
                PresentationsInboxView(
                    readyLessons: readyLessons,
                    blockedLessons: blockedLessons,
                    getBlockingContracts: getBlockingContracts,
                    filteredSnapshot: filteredSnapshot,
                    missWindow: missWindow,
                    missWindowRaw: $missWindowRaw,
                    selectedStudentLessonForDetail: $selectedStudentLessonForDetail,
                    isInboxTargeted: $isInboxTargeted
                )
                .frame(height: proxy.size.height * 0.5)
                Divider()
                // Bottom: Calendar strip (~50% height)
                PresentationsCalendarStrip(
                    days: days,
                    startDate: $startDate,
                    isNonSchool: isNonSchool,
                    onClear: { sl in
                        sl.scheduledFor = nil
                        try? modelContext.save()
                    },
                    onSelect: { sl in
                        selectedStudentLessonForDetail = sl
                    }
                )
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
            .presentationSizingFitted()
        #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
        }
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

}

