// swiftlint:disable file_length
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

enum PresentationsMissWindow: String, CaseIterable, Sendable {
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

// swiftlint:disable:next type_body_length
struct PresentationsView: View {
    private static let logger = Logger.presentations
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dependencies) private var dependencies

    // OPTIMIZATION: Use lightweight queries for change detection only
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    // The ViewModel handles all actual data loading with targeted fetches
    @Query(sort: [SortDescriptor(\LessonAssignment.id)])
    private var lessonAssignmentsForChangeDetection: [LessonAssignment]
    @Query(sort: [SortDescriptor(\Lesson.id)]) private var lessonsForChangeDetection: [Lesson]
    @Query(sort: [SortDescriptor(\Student.id)]) private var studentsForChangeDetection: [Student]
    @Query(sort: [SortDescriptor(\WorkModel.id)]) private var workModelsForChangeDetection: [WorkModel]

    private struct LessonAssignmentChangeKey: Hashable {
        let id: UUID
        let scheduledFor: Double
        let presentedAt: Double
        let stateRaw: String
    }

    private var lessonAssignmentChangeKeys: [LessonAssignmentChangeKey] {
        lessonAssignmentsForChangeDetection
            .map {
                LessonAssignmentChangeKey(
                    id: $0.id,
                    scheduledFor: $0.scheduledFor?.timeIntervalSinceReferenceDate ?? -1,
                    presentedAt: $0.presentedAt?.timeIntervalSinceReferenceDate ?? -1,
                    stateRaw: $0.stateRaw
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
    
    private var activeWorkIDs: [UUID] {
        workModelsForChangeDetection
            .filter { $0.statusRaw != "complete" }
            .map { $0.id }
    }
    
    // MODERN: Unified dependency tracker for ViewModel updates
    // Consolidates all onChange handlers into a single observation point
    private struct ViewModelDependencies: Equatable {
        let lessonAssignmentKeys: [LessonAssignmentChangeKey]
        let lessonIDs: [UUID]
        let studentIDs: [UUID]
        let activeWorkIDs: [UUID]
        let missWindowRaw: String
        let showTestStudents: Bool
        let testStudentNamesRaw: String
    }

    private var viewModelDependencies: ViewModelDependencies {
        ViewModelDependencies(
            lessonAssignmentKeys: lessonAssignmentChangeKeys,
            lessonIDs: lessonIDs,
            studentIDs: studentIDs,
            activeWorkIDs: activeWorkIDs,
            missWindowRaw: missWindowRaw,
            showTestStudents: showTestStudents,
            testStudentNamesRaw: testStudentNamesRaw
        )
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
        openWorkModels
            .filter { $0.presentationID != nil }
            .grouped { $0.presentationID ?? "" }
    }
    
    // NOTE: WorkModel fetching is now handled by ViewModel

    @AppStorage(UserDefaultsKeys.planningInboxOrder) private var inboxOrderRaw: String = ""
    @AppStorage(UserDefaultsKeys.lessonsAgendaStartDate) private var startDateRaw: Double = 0

    @AppStorage(UserDefaultsKeys.lessonsAgendaMissWindow)
    private var missWindowRaw: String = PresentationsMissWindow.all.rawValue
    @AppStorage(UserDefaultsKeys.planningRecentWindowDays) private var recentWindowDays: Int = 1

    private var missWindow: PresentationsMissWindow { PresentationsMissWindow(rawValue: missWindowRaw) ?? .all }

    private func syncRecentWindowWithMissWindow() {
        switch missWindow {
        case .all: recentWindowDays = 0
        case .d1: recentWindowDays = 1
        case .d2: recentWindowDays = 2
        case .d3: recentWindowDays = 3
        }
    }

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @State private var startDate: Date = Date()
    @State private var mobileViewSelection: MobileViewMode = .inbox
    @State private var cachedNonSchoolDates: Set<Date> = []
    
    // MODERN: Centralized navigation coordinator
    @State private var coordinator = PresentationsCoordinator()

    enum MobileViewMode: String, CaseIterable, Sendable {
        case inbox = "Inbox"
        case calendar = "Calendar"
    }
    
    // OPTIMIZATION: Use shared ViewModel from dependencies for instant loading
    // The shared instance persists across navigation and preloads data in the background
    private var viewModel: PresentationsViewModel {
        dependencies.presentationsViewModel
    }
    
    // Computed properties that use ViewModel (preserves exact same functionality)
    private var readyLessons: [LessonAssignment] { viewModel.readyLessons }
    private var blockedLessons: [LessonAssignment] { viewModel.blockedLessons }
    private func getBlockingWork(_ la: LessonAssignment) -> [UUID: WorkModel] {
        viewModel.getBlockingWork(la)
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
        // Strictly respect the startDate cursor. 
        // The logic to "start at earliest lesson" is handled by the initial value of startDate in onAppear.
        // This allows the user to click "Today" and actually go to today, even if there are older lessons.
        let baseDate = calendar.startOfDay(for: startDate)
        
        // Compute school days starting exactly at baseDate, extending forward
        var result: [Date] = []
        let maxDays = BackupConstants.maxCalendarDaysInGrid
        var cursor = baseDate
        var safety = 0
        
        while result.count < maxDays && safety < BatchingConstants.defaultBatchSize {
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
                            coordinator: coordinator,
                            cachedLessons: viewModel.lessons,
                            cachedStudents: viewModel.cachedStudents,
                            daysSinceLastLessonByStudent: daysSinceLastLessonByStudent
                        )
                    case .calendar:
                        PresentationsCalendarStrip(
                            days: days,
                            startDate: $startDate,
                            isNonSchool: isNonSchool,
                            onClear: { la in
                                la.unschedule()
                                do {
                                    try modelContext.save()
                                } catch {
                                    Self.logger.warning("Failed to save schedule clear: \(error)")
                                }
                            },
                            onSelect: { la in
                                coordinator.showLessonAssignmentDetail(la)
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
                        let inboxHeight = proxy.size.height * (coordinator.isCalendarMinimized ? 1.0 : 0.5)
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
                                coordinator: coordinator,
                                cachedLessons: viewModel.lessons,
                                cachedStudents: viewModel.cachedStudents,
                                daysSinceLastLessonByStudent: daysSinceLastLessonByStudent
                            )
                            .frame(height: inboxHeight)

                            if !coordinator.isCalendarMinimized {
                                Divider()
                                // Bottom: Calendar strip
                                PresentationsCalendarStrip(
                                    days: days,
                                    startDate: $startDate,
                                    isNonSchool: isNonSchool,
                                    onClear: { la in
                                        la.unschedule()
                                        do {
                                            try modelContext.save()
                                        } catch {
                                            Self.logger.warning("Failed to save schedule clear: \(error)")
                                        }
                                    },
                                    onSelect: { la in
                                        coordinator.showLessonAssignmentDetail(la)
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
                let earliestDate = lessonAssignmentsForChangeDetection
                    .compactMap { $0.scheduledFor }
                    .min()
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
        // MODERN: Single onChange for startDate (persists to @AppStorage and loads dates)
        .onChange(of: startDate) { _, new in
            Task { @MainActor in
                startDateRaw = new.timeIntervalSinceReferenceDate
                await loadNonSchoolDates()
            }
        }
        // MODERN: Unified dependency tracker - single onChange replaces 7 separate handlers
        // SwiftUI automatically recomputes viewModelDependencies when any component changes
        .onChange(of: viewModelDependencies) { old, new in
            // Sync inbox order when lesson assignments change
            if old.lessonAssignmentKeys != new.lessonAssignmentKeys {
                syncInboxOrderWithCurrentBase()
            }
            
            // Sync miss window when it changes
            if old.missWindowRaw != new.missWindowRaw {
                syncRecentWindowWithMissWindow()
            }
            
            // Update ViewModel for any dependency change
            updateViewModel()
        }
        // MODERN: Sheet presentation managed by coordinator
        .sheet(item: $coordinator.activeSheet) { sheet in
            switch sheet {
            case .lessonAssignmentDetail(let la):
                PresentationDetailView(lessonAssignment: la) {
                    coordinator.dismissSheet()
                }
                #if os(macOS)
                .presentationSizingFitted()
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif

            case .schedulePresentationFor(let lesson):
                SchedulePresentationSheet(
                    lesson: lesson,
                    onPlan: { _ in coordinator.dismissSheet() },
                    onCancel: { coordinator.dismissSheet() }
                )

            case .postPresentation, .unifiedWorkflow, .lessonAssignmentHistory:
                Text("Sheet not yet implemented")
            }
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
        // Fetch only unscheduled, non-presented lesson assignments for inbox ordering
        let draftRaw = LessonAssignmentState.draft.rawValue
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.stateRaw == draftRaw }
        )
        let base: [LessonAssignment]
        do {
            base = try modelContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch unscheduled lessons: \(error)")
            base = []
        }
        let baseIDs = base.map { $0.id }
        var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
        let missing = base
            .filter { !order.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.id }
        order.append(contentsOf: missing)
        inboxOrderRaw = InboxOrderStore.serialize(order)
    }

    private func filteredSnapshot(_ la: LessonAssignment) -> LessonAssignmentSnapshot {
        let snap = la.snapshot()
        // Use ViewModel's cached students (avoids redundant fetching)
        let allStudents = viewModel.cachedStudents
        let hiddenIDs = TestStudentsFilter.hiddenIDs(
            from: allStudents, show: showTestStudents, namesRaw: testStudentNamesRaw
        )
        let visibleIDs = snap.studentIDs.filter { !hiddenIDs.contains($0) }
        return LessonAssignmentSnapshot(
            id: snap.id,
            lessonID: snap.lessonID,
            studentIDs: visibleIDs,
            createdAt: snap.createdAt,
            scheduledFor: snap.scheduledFor,
            presentedAt: snap.presentedAt,
            state: snap.state,
            notes: snap.notes,
            needsPractice: snap.needsPractice,
            needsAnotherPresentation: snap.needsAnotherPresentation,
            followUpWork: snap.followUpWork,
            manuallyUnblocked: snap.manuallyUnblocked
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
