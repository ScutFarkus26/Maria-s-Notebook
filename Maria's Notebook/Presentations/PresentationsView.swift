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

    // OPTIMIZATION: Use lightweight queries for change detection only
    // These queries only track IDs/counts to detect changes, not load all data
    // The ViewModel does targeted fetching with predicates
    @Query private var studentLessonIDs: [StudentLesson]
    @Query private var lessonIDs: [Lesson]
    @Query private var studentIDs: [Student]
    
    // OPTIMIZATION: Only fetch active/review contracts (needed for blocking logic)
    // Split into separate queries to help compiler type-check
    @Query(filter: #Predicate<WorkContract> { $0.statusRaw == "active" }) 
    private var activeContractsOnly: [WorkContract]
    
    @Query(filter: #Predicate<WorkContract> { $0.statusRaw == "review" }) 
    private var reviewContractsOnly: [WorkContract]
    
    // Computed property to combine them
    private var activeContracts: [WorkContract] {
        activeContractsOnly + reviewContractsOnly
    }

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
    
    // OPTIMIZATION: Use ViewModel to cache expensive computations
    @StateObject private var viewModel = PresentationsViewModel()

    // Age settings
    @AppStorage("LessonAge.warningDays") private var ageWarningDays: Int = LessonAgeDefaults.warningDays
    @AppStorage("LessonAge.overdueDays") private var ageOverdueDays: Int = LessonAgeDefaults.overdueDays
    @AppStorage("LessonAge.freshColorHex") private var ageFreshHex: String = LessonAgeDefaults.freshColorHex
    @AppStorage("LessonAge.warningColorHex") private var ageWarningHex: String = LessonAgeDefaults.warningColorHex
    @AppStorage("LessonAge.overdueColorHex") private var ageOverdueHex: String = LessonAgeDefaults.overdueColorHex
    
    // Computed properties that use ViewModel (preserves exact same functionality)
    private var readyLessons: [StudentLesson] { viewModel.readyLessons }
    private var blockedLessons: [StudentLesson] { viewModel.blockedLessons }
    private func getBlockingContracts(_ sl: StudentLesson) -> [UUID: WorkContract] {
        viewModel.getBlockingContracts(sl)
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

    // Use ViewModel's cached value (preserves exact same functionality)
    private var daysSinceLastLessonByStudent: [UUID: Int] {
        viewModel.daysSinceLastLessonByStudent
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
            
            // Update ViewModel with initial data
            updateViewModel()
        }
        .onChange(of: startDate) { _, new in
            startDateRaw = new.timeIntervalSinceReferenceDate
        }
        .onChange(of: studentLessonIDs.map { $0.id }) { _, _ in
            syncInboxOrderWithCurrentBase()
            updateViewModel()
        }
        .onChange(of: lessonIDs.map { $0.id }) { _, _ in
            updateViewModel()
        }
        .onChange(of: activeContracts.map { $0.id }) { _, _ in
            updateViewModel()
        }
        .onChange(of: studentIDs.map { $0.id }) { _, _ in
            updateViewModel()
        }
        .onChange(of: missWindowRaw) { _, _ in
            syncRecentWindowWithMissWindow()
            updateViewModel()
        }
        .onChange(of: showTestStudents) { _, _ in
            updateViewModel()
        }
        .onChange(of: testStudentNamesRaw) { _, _ in
            updateViewModel()
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
    
    /// Update ViewModel - now fetches data internally with targeted queries
    private func updateViewModel() {
        viewModel.update(
            modelContext: modelContext,
            calendar: calendar,
            inboxOrderRaw: inboxOrderRaw,
            missWindow: missWindow,
            showTestStudents: showTestStudents,
            testStudentNamesRaw: testStudentNamesRaw
        )
    }
    
    private func syncInboxOrderWithCurrentBase() {
        // Fetch only unscheduled, non-given lessons for inbox ordering
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.scheduledFor == nil && $0.isPresented == false && $0.givenAt == nil }
        )
        let base = (try? modelContext.fetch(descriptor)) ?? []
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
        // Fetch students only when needed for filtering
        let allStudents = (try? modelContext.fetch(FetchDescriptor<Student>())) ?? []
        let hiddenIDs = TestStudentsFilter.hiddenIDs(from: allStudents, show: showTestStudents, namesRaw: testStudentNamesRaw)
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

