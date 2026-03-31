import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

struct PresentationsView: View {
    static let logger = Logger.presentations
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.calendar) var calendar
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.dependencies) private var dependencies

    // OPTIMIZATION: Use lightweight queries for change detection only
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    // The ViewModel handles all actual data loading with targeted fetches
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)])
    var lessonAssignmentsForChangeDetection: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.id, ascending: true)]) private var lessonsForChangeDetection: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.id, ascending: true)]) private var studentsForChangeDetection: FetchedResults<CDStudent>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.id, ascending: true)]) private var workModelsForChangeDetection: FetchedResults<CDWorkModel>

    struct LessonAssignmentChangeKey: Hashable {
        let id: UUID
        let scheduledFor: Double
        let presentedAt: Double
        let stateRaw: String
    }

    private var lessonAssignmentChangeKeys: [LessonAssignmentChangeKey] {
        lessonAssignmentsForChangeDetection
            .compactMap { la -> LessonAssignmentChangeKey? in
                guard let id = la.id else { return nil }
                return LessonAssignmentChangeKey(
                    id: id,
                    scheduledFor: la.scheduledFor?.timeIntervalSinceReferenceDate ?? -1,
                    presentedAt: la.presentedAt?.timeIntervalSinceReferenceDate ?? -1,
                    stateRaw: la.stateRaw
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private var lessonIDs: [UUID] {
        lessonsForChangeDetection.compactMap(\.id)
    }

    private var studentIDs: [UUID] {
        studentsForChangeDetection.compactMap(\.id)
    }

    private var activeWorkIDs: [UUID] {
        workModelsForChangeDetection
            .filter { $0.statusRaw != "complete" }
            .compactMap(\.id)
    }

    // MODERN: Unified dependency tracker for ViewModel updates
    // Consolidates all onChange handlers into a single observation point
    struct ViewModelDependencies: Equatable {
        let lessonAssignmentKeys: [LessonAssignmentChangeKey]
        let lessonIDs: [UUID]
        let studentIDs: [UUID]
        let activeWorkIDs: [UUID]
        let missWindowRaw: String
        let showTestStudents: Bool
        let testStudentNamesRaw: String
    }

    var viewModelDependencies: ViewModelDependencies {
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
    private var activeWork: [CDWorkModel] {
        workModelsForChangeDetection.filter { $0.statusRaw != "complete" }
    }

    // Helper: All WorkModels from the existing @Query
    private var allWorkModels: [CDWorkModel] {
        Array(workModelsForChangeDetection)
    }

    // Helper: Open WorkModels (statusRaw != "complete")
    private var openWorkModels: [CDWorkModel] {
        allWorkModels.filter { $0.statusRaw != "complete" }
    }

    // Dictionary for fast lookup: Group open WorkModels by presentationID
    private var openWorkByPresentationID: [String: [CDWorkModel]] {
        openWorkModels
            .filter { $0.presentationID != nil }
            .grouped { $0.presentationID ?? "" }
    }

    // NOTE: CDWorkModel fetching is now handled by ViewModel

    @AppStorage(UserDefaultsKeys.planningInboxOrder) var inboxOrderRaw: String = ""
    @AppStorage(UserDefaultsKeys.lessonsAgendaStartDate) var startDateRaw: Double = 0

    @AppStorage(UserDefaultsKeys.lessonsAgendaMissWindow)
    var missWindowRaw: String = PresentationsMissWindow.all.rawValue
    @AppStorage(UserDefaultsKeys.planningRecentWindowDays) private var recentWindowDays: Int = 1

    var missWindow: PresentationsMissWindow { PresentationsMissWindow(rawValue: missWindowRaw) ?? .all }

    func syncRecentWindowWithMissWindow() {
        switch missWindow {
        case .all: recentWindowDays = 0
        case .d1: recentWindowDays = 1
        case .d2: recentWindowDays = 2
        case .d3: recentWindowDays = 3
        }
    }

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @State var startDate: Date = Date()
    @State var mobileViewSelection: MobileViewMode = .inbox
    @State var cachedNonSchoolDates: Set<Date> = []

    // MODERN: Centralized navigation coordinator
    @State var coordinator = PresentationsCoordinator()

    enum MobileViewMode: String, CaseIterable, Sendable {
        case inbox = "Inbox"
        case calendar = "Calendar"
    }

    // OPTIMIZATION: Use shared ViewModel from dependencies for instant loading
    // The shared instance persists across navigation and preloads data in the background
    var viewModel: PresentationsViewModel {
        dependencies.presentationsViewModel
    }

    // Computed properties that use ViewModel (preserves exact same functionality)
    var readyLessons: [CDLessonAssignment] { viewModel.readyLessons }
    var blockedLessons: [CDLessonAssignment] { viewModel.blockedLessons }
    func getBlockingWork(_ la: CDLessonAssignment) -> [UUID: CDWorkModel] {
        viewModel.getBlockingWork(la)
    }

    func isNonSchool(_ day: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        return cachedNonSchoolDates.contains(dayStart)
    }

    func loadNonSchoolDates() async {
        let baseDate = calendar.startOfDay(for: startDate)
        // Load enough dates to cover the days array (14 school days might span ~20 calendar days)
        let endDate = calendar.date(byAdding: .day, value: 30, to: baseDate) ?? baseDate
        let set = await SchoolCalendar.nonSchoolDays(in: baseDate..<endDate, using: viewContext)
        await MainActor.run { cachedNonSchoolDates = set }
    }

    // Find the earliest date with a scheduled lesson (using ViewModel's cached data)
    private var earliestDateWithLesson: Date? {
        viewModel.earliestDateWithLesson(calendar: calendar)
    }

    var days: [Date] {
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
    var daysSinceLastLessonByStudent: [UUID: Int] {
        viewModel.daysSinceLastLessonByStudent
    }

    // MARK: - body is defined in PresentationsView+Body.swift
}
