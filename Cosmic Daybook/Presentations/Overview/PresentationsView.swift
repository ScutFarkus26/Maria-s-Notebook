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
    @Environment(SaveCoordinator.self) var saveCoordinator
    #if os(macOS)
    @Environment(\.openWindow) var openWindow
    #endif

    var embeddedSearchText: String?
    var focusedPresentationID: UUID?
    /// Owned by the To Schedule pane so the waiting-students rail beside this
    /// view can drive the same student filter and the same search.
    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState
    /// Command-click selection, owned by the workspace so it survives a switch
    /// between the two halves.
    let selection: WorkspaceMultiSelection

    /// Bumped whenever a lesson assignment, lesson, student or work model
    /// changes anywhere this screen could see it (`onPresentationDataChange`
    /// in the body). Four whole-table `@FetchRequest`s used to sit here so a
    /// body pass could walk every row into change keys; the signal now
    /// arrives only when one of those tables moved, and says which.
    @State var changeToken = 0
    /// Bumped only when an assignment moved: the inbox order and the
    /// deep-link reveal read assignments, so the other three tables leave
    /// them alone.
    @State var assignmentChangeToken = 0

    // MODERN: Unified dependency tracker for ViewModel updates
    // Consolidates all onChange handlers into a single observation point
    struct ViewModelDependencies: Equatable {
        let changeToken: Int
        let assignmentChangeToken: Int
        let missWindowRaw: String
        let showTestStudents: Bool
        let testStudentNamesRaw: String
    }

    var viewModelDependencies: ViewModelDependencies {
        ViewModelDependencies(
            changeToken: changeToken,
            assignmentChangeToken: assignmentChangeToken,
            missWindowRaw: missWindowRaw,
            showTestStudents: testStudents.show,
            testStudentNamesRaw: testStudents.namesRaw
        )
    }

    // NOTE: CDWorkModel fetching is handled by the ViewModel

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

    @TestStudentVisibility var testStudents

    /// Debounces `updateViewModel()` calls triggered by `viewModelDependencies`
    /// changes. A single CloudKit import can bump `changeToken` several times
    /// in quick succession — without debouncing, each bump triggers a full
    /// PresentationsViewModel rebuild.
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
