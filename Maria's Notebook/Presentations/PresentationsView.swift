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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // OPTIMIZATION: Use lightweight queries for change detection only
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    // The ViewModel handles all actual data loading with targeted fetches
    @Query(sort: [SortDescriptor(\StudentLesson.id)]) private var studentLessonsForChangeDetection: [StudentLesson]
    @Query(sort: [SortDescriptor(\Lesson.id)]) private var lessonsForChangeDetection: [Lesson]
    @Query(sort: [SortDescriptor(\Student.id)]) private var studentsForChangeDetection: [Student]
    @Query(sort: [SortDescriptor(\WorkModel.id)]) private var workModelsForChangeDetection: [WorkModel]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var studentLessonIDs: [UUID] {
        studentLessonsForChangeDetection.map { $0.id }
    }
    
    private struct StudentLessonChangeKey: Hashable {
        let id: UUID
        let scheduledFor: Double
        let givenAt: Double
        let isPresented: Bool
    }
    
    private var studentLessonChangeKeys: [StudentLessonChangeKey] {
        studentLessonsForChangeDetection
            .map {
                StudentLessonChangeKey(
                    id: $0.id,
                    scheduledFor: $0.scheduledFor?.timeIntervalSinceReferenceDate ?? -1,
                    givenAt: $0.givenAt?.timeIntervalSinceReferenceDate ?? -1,
                    isPresented: $0.isPresented
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
    
    private var lessonIDs: [UUID] {
        lessonsForChangeDetection.map { $0.id }
    }
    
    private var studentIDs: [UUID] {
        studentsForChangeDetection.map { $0.id }
    }
    
    // Active WorkModels: unresolved work items (statusRaw != "complete")
    private var activeWork: [WorkModel] {
        workModelsForChangeDetection.filter { $0.statusRaw != "complete" }
    }
    
    // Helper: All WorkModels from the existing @Query
    private var allWorkModels: [WorkModel] {
        workModelsForChangeDetection
    }
    
    // Helper: Open WorkModels (statusRaw != "complete")
    private var openWorkModels: [WorkModel] {
        allWorkModels.filter { $0.statusRaw != "complete" }
    }
    
    // Dictionary for fast lookup: Group open WorkModels by presentationID
    private var openWorkByPresentationID: [String: [WorkModel]] {
        Dictionary(grouping: openWorkModels.filter { $0.presentationID != nil }) { work in
            work.presentationID ?? ""
        }
    }
    
    // NOTE: WorkModel fetching is now handled by ViewModel

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
    @State private var isCalendarMinimized: Bool = false
    @State private var mobileViewSelection: MobileViewMode = .inbox
    @State private var cachedNonSchoolDates: Set<Date> = []
    
    enum MobileViewMode: String, CaseIterable {
        case inbox = "Inbox"
        case calendar = "Calendar"
    }
    
    // OPTIMIZATION: Use ViewModel to cache expensive computations
    @StateObject private var viewModel = PresentationsViewModel()
    
    // Computed properties that use ViewModel (preserves exact same functionality)
    private var readyLessons: [StudentLesson] { viewModel.readyLessons }
    private var blockedLessons: [StudentLesson] { viewModel.blockedLessons }
    private func getBlockingWork(_ sl: StudentLesson) -> [UUID: WorkModel] {
        viewModel.getBlockingWork(sl)
    }

    private func isNonSchool(_ day: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        return cachedNonSchoolDates.contains(dayStart)
    }
    
    private func loadNonSchoolDates() async {
        let baseDate = calendar.startOfDay(for: startDate)
        // Load enough dates to cover the days array (14 school days might span ~20 calendar days)
        let endDate = calendar.date(byAdding: .day, value: 30, to: baseDate) ?? baseDate
        let set = await SchoolCalendar.nonSchoolDays(in: baseDate..<endDate, using: modelContext)
        await MainActor.run { cachedNonSchoolDates = set }
    }

    // Find the earliest date with a scheduled lesson (using ViewModel's cached data)
    private var earliestDateWithLesson: Date? {
        viewModel.earliestDateWithLesson(calendar: calendar)
    }
    
    private var days: [Date] {
        // FIXED: Strictly respect the startDate cursor. 
        // The logic to "start at earliest lesson" is handled by the initial value of startDate in onAppear.
        // This allows the user to click "Today" and actually go to today, even if there are older lessons.
        let baseDate = calendar.startOfDay(for: startDate)
        
        // Compute school days starting exactly at baseDate, extending forward
        var result: [Date] = []
        let maxDays = 14
        var cursor = baseDate
        var safety = 0
        
        while result.count < maxDays && safety < 1000 {
            if !isNonSchool(cursor) {
                result.append(cursor)
            }
            if let next = calendar.date(byAdding: .day, value: 1, to: cursor) {
                cursor = next
            } else {
                break
            }
            safety += 1
        }
        
        return result
    }

    // Use ViewModel's cached value (preserves exact same functionality)
    private var daysSinceLastLessonByStudent: [UUID: Int] {
        viewModel.daysSinceLastLessonByStudent
    }


    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                // iPhone Layout: Segmented Control approach
                VStack(spacing: 0) {
                    Picker("View", selection: $mobileViewSelection) {
                        ForEach(MobileViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    switch mobileViewSelection {
                    case .inbox:
                        PresentationsInboxView(
                            readyLessons: readyLessons,
                            blockedLessons: blockedLessons,
                            getBlockingWork: getBlockingWork,
                            filteredSnapshot: filteredSnapshot,
                            missWindow: missWindow,
                            missWindowRaw: $missWindowRaw,
                            selectedStudentLessonForDetail: $selectedStudentLessonForDetail,
                            isInboxTargeted: $isInboxTargeted,
                            isCalendarMinimized: .constant(false) // Always expanded in this mode
                        )
                    case .calendar:
                        PresentationsCalendarStrip(
                            days: days,
                            startDate: $startDate,
                            isNonSchool: isNonSchool,
                            onClear: { sl in
                                sl.scheduledFor = nil
                                #if DEBUG
                                sl.checkInboxInvariant()
                                #endif
                                try? modelContext.save()
                            },
                            onSelect: { sl in
                                selectedStudentLessonForDetail = sl
                            }
                        )
                    }
                }
            } else {
                // macOS / iPad Layout: Existing Split View
                VStack(spacing: 0) {
                    ViewHeader(title: "Presentations")
                    Divider()
                    GeometryReader { proxy in
                        let inboxHeight = proxy.size.height * (isCalendarMinimized ? 1.0 : 0.5)
                        let calendarHeight = proxy.size.height * 0.5

                        VStack(spacing: 0) {
                            // Top: Inbox
                            PresentationsInboxView(
                                readyLessons: readyLessons,
                                blockedLessons: blockedLessons,
                                getBlockingWork: getBlockingWork,
                                filteredSnapshot: filteredSnapshot,
                                missWindow: missWindow,
                                missWindowRaw: $missWindowRaw,
                                selectedStudentLessonForDetail: $selectedStudentLessonForDetail,
                                isInboxTargeted: $isInboxTargeted,
                                isCalendarMinimized: $isCalendarMinimized
                            )
                            .frame(height: inboxHeight)

                            if !isCalendarMinimized {
                                Divider()
                                // Bottom: Calendar strip
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
                                .frame(height: calendarHeight)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                    }
                }
            }
        }
        .task {
            // Update ViewModel immediately
            updateViewModel()
            
            if startDateRaw != 0 {
                startDate = Date(timeIntervalSinceReferenceDate: startDateRaw)
            } else {
                // Calculate earliest lesson date locally using the @Query data directly
                // (The ViewModel might not be ready yet for this specific check)
                let earliestDate = studentLessonsForChangeDetection
                    .compactMap { $0.scheduledFor } // Get all scheduled dates
                    .min() // Find the earliest
                    .map { calendar.startOfDay(for: $0) }
                
                let today = calendar.startOfDay(for: Date())
                
                if let earliest = earliestDate {
                    // Start at the earliest lesson, or today if lessons are in the future
                    startDate = min(earliest, today)
                } else {
                    // No lessons? Start at today (adjusted for school days)
                    // First load non-school dates, then compute initial start date
                    await loadNonSchoolDates()
                    startDate = AgendaSchoolDayRules.computeInitialStartDate(
                        calendar: calendar,
                        isNonSchoolDay: isNonSchool
                    )
                }
                startDateRaw = startDate.timeIntervalSinceReferenceDate
            }
            
            // Load non-school dates for the current startDate
            await loadNonSchoolDates()
            
            syncInboxOrderWithCurrentBase()
            syncRecentWindowWithMissWindow()
        }
        .onChange(of: startDate) { _, new in
            startDateRaw = new.timeIntervalSinceReferenceDate
            Task {
                await loadNonSchoolDates()
            }
        }
        .onChange(of: studentLessonChangeKeys) { _, _ in
            syncInboxOrderWithCurrentBase()
            updateViewModel()
        }
        .onChange(of: lessonIDs) { _, _ in
            updateViewModel()
        }
        .onChange(of: activeWork.map { $0.id }) { _, _ in
            updateViewModel()
        }
        .onChange(of: studentIDs) { _, _ in
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

    private func filteredSnapshot(_ sl: StudentLesson) -> StudentLessonSnapshot {
        let snap = sl.snapshot()
        // Use ViewModel's cached students (avoids redundant fetching)
        let allStudents = viewModel.cachedStudents
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
    
    // MARK: - Helper Functions
    
    static func unresolvedWorkCount(forPresentationID pid: String, studentIDs: [String], allWork: [WorkModel]) -> Int {
        return allWork.filter { w in
            w.presentationID == pid &&
            studentIDs.contains(w.studentID) &&
            w.statusRaw != "complete"
        }.count
    }

}

