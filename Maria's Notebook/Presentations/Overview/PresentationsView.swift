import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

/// The Upcoming pane of the Lessons & Work workspace.
///
/// This view is only ever rendered inside `WorksAgendaView`. It used to double
/// as a standalone screen with its own header and a Plan / Follow Up mode
/// toggle; that form became unreachable when the workspace absorbed it, and the
/// follow-up half now lives in the Attention list.
struct PresentationsView: View {
    static let logger = Logger.presentations
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.calendar) var calendar
    @Environment(\.appRouter) var appRouter
    @Environment(\.dependencies) private var dependencies
    #if os(macOS)
    @Environment(\.openWindow) var openWindow
    #endif

    var embeddedSearchText: String? = nil
    var focusedPresentationID: UUID? = nil
    /// Owned by the To Schedule pane so the waiting-students rail beside this
    /// view can drive the same student filter and the same search.
    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState
    /// Command-click selection, owned by the workspace so it survives a switch
    /// between the two halves.
    let selection: WorkspaceMultiSelection

    // OPTIMIZATION: Use lightweight queries for change detection only
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    // The ViewModel handles all actual data loading with targeted fetches
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)])
    var lessonAssignmentsForChangeDetection: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.id, ascending: true)])
    private var lessonsForChangeDetection: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.id, ascending: true)])
    private var studentsForChangeDetection: FetchedResults<CDStudent>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.id, ascending: true)])
    private var workModelsForChangeDetection: FetchedResults<CDWorkModel>

    struct LessonAssignmentChangeKey: Hashable {
        let id: UUID
        let scheduledFor: Double
        let presentedAt: Double
        let stateRaw: String
    }

    /// `viewModelDependencies` is read by `.onChange`, so SwiftUI rebuilds this on
    /// every body pass to diff it. It used to end in `.sorted { $0.id.uuidString <
    /// $1.id.uuidString }`, which allocated two 36-character strings per comparison —
    /// roughly `2 · n · log₂(n)` string allocations across the whole assignment table,
    /// every pass. The sort was also redundant: the fetch above already orders by
    /// `\CDLessonAssignment.id`, so the array is a deterministic function of the data
    /// either way, which is all an equality-compared change key needs.
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

    /// Debounces `updateViewModel()` calls triggered by `viewModelDependencies`
    /// changes. A single CloudKit import that touches unrelated entities can
    /// fire several @FetchRequest updates in quick succession — without
    /// debouncing, each one triggers a full PresentationsViewModel rebuild.
    @State var dependencyDebounceTask: Task<Void, Never>?

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

    // Use ViewModel's cached value (preserves exact same functionality)
    var daysSinceLastLessonByStudent: [UUID: Int] {
        viewModel.daysSinceLastLessonByStudent
    }

    // MARK: - body is defined in PresentationsView+Body.swift

    /// True when the Ready list is capable of revealing this presentation.
    ///
    /// A given presentation is history and a scheduled one belongs to the
    /// Scheduled calendar, so neither can be shown here — claiming them would
    /// leave a deep link pointing at a list that does not contain the record.
    static func canRevealInReadyList(isPresented: Bool, scheduledFor: Date?) -> Bool {
        !isPresented && scheduledFor == nil
    }

    /// Which pill can show this presentation, or nil when none can.
    ///
    /// A given one carries its unresolved responsibility, which is what the
    /// Follow Up pill holds; an unscheduled one is in the planning inbox; a
    /// scheduled one belongs to the Scheduled calendar pinned below, so no pill
    /// here claims it.
    static func chipRevealing(
        isPresented: Bool,
        scheduledFor: Date?
    ) -> PresentationsFilterChip? {
        if isPresented { return .followUp }
        return canRevealInReadyList(isPresented: isPresented, scheduledFor: scheduledFor)
            ? .all
            : nil
    }
}
