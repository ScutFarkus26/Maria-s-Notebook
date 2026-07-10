import Foundation
import CoreData
import SwiftUI
import OSLog

/// Central dependency injection container for the application.
///
/// This container provides lazy initialization of all services and manages their lifecycle.
/// Services are instantiated only when first accessed, reducing startup time.
///
/// **Usage:**
/// ```swift
/// @main
/// struct MariasNotebookApp: App {
///     let coreDataStack: CoreDataStack
///     let dependencies: AppDependencies
///
///     init() {
///         coreDataStack = AppBootstrapping.getSharedCoreDataStack()
///         dependencies = AppDependencies(coreDataStack: coreDataStack)
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             RootView()
///                 .environment(\.managedObjectContext, coreDataStack.viewContext)
///                 .environment(\.dependencies, dependencies)
///         }
///     }
/// }
/// ```
///
/// **In Views:**
/// ```swift
/// struct TodayView: View {
///     @Environment(\.dependencies) private var dependencies
///
///     var body: some View {
///         // Use services from dependencies
///         Button("Sync") {
///             dependencies.reminderSync.syncReminders()
///         }
///     }
/// }
/// ```
@Observable
@MainActor
final class AppDependencies {
    private static let logger = Logger.app_

    /// The Core Data stack powering all persistence.
    let coreDataStack: CoreDataStack

    /// Convenience accessor for the view context.
    var viewContext: NSManagedObjectContext { coreDataStack.viewContext }

    // MARK: - Initialization

    @ObservationIgnored
    private var schoolDayChangeObserver: (any NSObjectProtocol)?

    init(coreDataStack: CoreDataStack) {
        self.coreDataStack = coreDataStack

        // Invalidate cached school-day calculations whenever the underlying
        // calendar data changes — a local edit or a CloudKit sync. This is the
        // app-wide consumer of `.schoolDayDataDidChange`.
        schoolDayChangeObserver = NotificationCenter.default.addObserver(
            forName: .schoolDayDataDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.invalidateSchoolDayCaches() }
        }
    }

    // MARK: - Core Services

    private var _memoryPressureMonitor: MemoryPressureMonitor?
    var memoryPressureMonitor: MemoryPressureMonitor {
        if let monitor = _memoryPressureMonitor {
            return monitor
        }
        let monitor = MemoryPressureMonitor()
        monitor.startMonitoring { [weak self] level in
            self?.handleMemoryPressure(level: level)
        }
        _memoryPressureMonitor = monitor
        return monitor
    }

    // MARK: - Repositories

    /// Central repository container for type-safe data access
    /// Provides repositories for all entities with consistent context injection
    private var _repositories: RepositoryContainer?
    var repositories: RepositoryContainer {
        if let container = _repositories {
            return container
        }
        let container = RepositoryContainer(context: coreDataStack.viewContext, saveCoordinator: nil)
        _repositories = container
        return container
    }

    // MARK: - Data Services

    // Work-related services
    // CDNote: WorkCompletionService is an enum with static methods,
    // access directly (e.g., WorkCompletionService.someMethod())

    // MARK: - Protocol-Based Services

    /// WorkCheckInService - Protocol-based architecture
    var workCheckInService: any WorkCheckInServiceProtocol {
        WorkCheckInService(context: viewContext)
    }

    /// WorkStepService - Protocol-based architecture
    var workStepService: any WorkStepServiceProtocol {
        WorkStepService(context: viewContext)
    }

    // CDTrackEntity services
    private var _groupTrackService: SequenceTrackService?
    var groupTrackService: SequenceTrackService {
        if let service = _groupTrackService {
            return service
        }
        let service = SequenceTrackService()
        _groupTrackService = service
        return service
    }

    private var _trackProgressResolver: TrackProgressResolver?
    var trackProgressResolver: TrackProgressResolver {
        if let resolver = _trackProgressResolver {
            return resolver
        }
        let resolver = TrackProgressResolver()
        _trackProgressResolver = resolver
        return resolver
    }

    // MARK: - Sync Services

    private var _reminderSyncService: ReminderSyncService?
    var reminderSync: ReminderSyncService {
        if let service = _reminderSyncService {
            return service
        }
        let service = ReminderSyncService.shared
        service.managedObjectContext = viewContext
        _reminderSyncService = service
        return service
    }

    private var _calendarSyncService: CalendarSyncService?
    var calendarSync: CalendarSyncService {
        if let service = _calendarSyncService {
            return service
        }
        let service = CalendarSyncService()
        _calendarSyncService = service
        return service
    }

    // MARK: - Backup Services (backing stores for AppDependencies+BackupServices.swift)

    var _backupService: BackupService?
    var _backupTransactionManager: BackupTransactionManager?
    var _autoBackupManager: AutoBackupManager?
    var _backupCoordinator: BackupCoordinator?

    // MARK: - Migration Services

    var dataMigrations: DataMigrations.Type {
        DataMigrations.self
    }

    // MARK: - Business Logic Services

    private var _followUpInboxEngine: FollowUpInboxEngine?
    var followUpInboxEngine: FollowUpInboxEngine {
        if let engine = _followUpInboxEngine {
            return engine
        }
        let engine = FollowUpInboxEngine()
        _followUpInboxEngine = engine
        return engine
    }

    // MARK: - AI Services (backing stores for AppDependencies+AIServices.swift)

    var _aiRouter: AIClientRouter?
    var _chatService: ChatService?
    var _studentAnalysisService: StudentAnalysisService?
    var _lessonPlanningService: LessonPlanningService?
    var _reportGeneratorService: ReportGeneratorService?
    var _meetingInsightsService: MeetingInsightsService?

    // MARK: - UI Services

    private var _toastService: ToastService?
    var toastService: ToastService {
        if let service = _toastService {
            return service
        }
        let service = ToastService.shared
        _toastService = service
        return service
    }

    // MARK: - Storage Services

    // PhotoStorageService is an enum with static methods, no initialization needed
    // Access methods directly via PhotoStorageService.methodName()

    // MARK: - Calendar Services

    private var _schoolCalendarService: SchoolCalendarService?
    var schoolCalendarService: SchoolCalendarService {
        if let service = _schoolCalendarService {
            return service
        }
        let service = SchoolCalendarService.shared
        _schoolCalendarService = service
        return service
    }

    private var _schoolDayLookupCache: SchoolDayLookupCache?
    var schoolDayLookupCache: SchoolDayLookupCache {
        if let cache = _schoolDayLookupCache {
            return cache
        }
        let cache = SchoolDayLookupCache()
        _schoolDayLookupCache = cache
        return cache
    }

    /// The global "viewing year" lens shared by every screen.
    /// See Documentation/Implementation/SCHOOL_YEAR_SEPARATION.md.
    private var _schoolYearStore: SchoolYearStore?
    var schoolYearStore: SchoolYearStore {
        if let store = _schoolYearStore {
            return store
        }
        let store = SchoolYearStore()
        _schoolYearStore = store
        return store
    }

    // MARK: - Presentation Services

    private var _presentationsViewModel: PresentationsViewModel?
    var presentationsViewModel: PresentationsViewModel {
        if let vm = _presentationsViewModel {
            return vm
        }
        let vm = PresentationsViewModel()
        _presentationsViewModel = vm
        return vm
    }

    // MARK: - CloudKit Services

    // CloudKitConfigurationService is an enum with static methods, no initialization needed
    // Access methods directly via CloudKitConfigurationService.methodName()

    private var _cloudKitSyncStatusService: CloudKitSyncStatusService?
    var cloudKitSyncStatusService: CloudKitSyncStatusService {
        if let service = _cloudKitSyncStatusService {
            return service
        }
        let service = CloudKitSyncStatusService()
        _cloudKitSyncStatusService = service
        return service
    }

    private var _classroomSharingService: ClassroomSharingService?
    var classroomSharingService: ClassroomSharingService {
        if let service = _classroomSharingService {
            return service
        }
        let service = ClassroomSharingService(
            container: coreDataStack.container,
            context: viewContext,
            coreDataStack: coreDataStack
        )
        _classroomSharingService = service
        return service
    }

    /// Singleton accessor for the observable shared-store zone repair
    /// service. Surfaces orphan counts and unrecoverable records to the
    /// UI so the lead guide can see when their data isn't syncing.
    var sharedStoreZoneRepair: SharedStoreZoneRepair {
        SharedStoreZoneRepair.shared
    }

    // MARK: - Router & Coordinators

    private var _appRouter: AppRouter?
    var appRouter: AppRouter {
        if let router = _appRouter {
            return router
        }
        let router = AppRouter.shared
        _appRouter = router
        return router
    }

    private var _saveCoordinator: SaveCoordinator?
    var saveCoordinator: SaveCoordinator {
        if let coordinator = _saveCoordinator {
            return coordinator
        }
        let coordinator = SaveCoordinator()
        _saveCoordinator = coordinator
        return coordinator
    }

    private var _restoreCoordinator: RestoreCoordinator?
    var restoreCoordinator: RestoreCoordinator {
        if let coordinator = _restoreCoordinator {
            return coordinator
        }
        let coordinator = RestoreCoordinator()
        _restoreCoordinator = coordinator
        return coordinator
    }

    // MARK: - Testing Support

    /// Create dependencies with in-memory Core Data storage for testing
    static func makeTest() throws -> AppDependencies {
        let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
        return AppDependencies(coreDataStack: stack)
    }

    /// Create dependencies with specific CoreDataStack for testing
    static func makeTest(coreDataStack: CoreDataStack) -> AppDependencies {
        return AppDependencies(coreDataStack: coreDataStack)
    }

    // MARK: - Memory Pressure Handling

    /// Called when system memory pressure is detected.
    /// Clears caches proportionally to the pressure level to avoid termination.
    /// Clears every retained school-day cache and bumps the data-version stamp
    /// that lightweight per-instance caches (`SchoolDayCache`) check. Called on
    /// memory pressure and whenever the underlying calendar data changes (a local
    /// edit or a CloudKit sync), so calendar-dependent counts never go stale.
    func invalidateSchoolDayCaches() {
        SchoolDayCalculationCache.shared.invalidate()
        _schoolDayLookupCache?.invalidate()
        _schoolCalendarService?.invalidateCache()
        SchoolDayDataVersion.bump()
    }

    private func handleMemoryPressure(level: MemoryPressureLevel) {
        // Always: clear the in-memory image cache (NSCache).
        // NSCache auto-evicts under pressure, but an explicit call ensures it happens now.
        ImageCache.shared.removeAllObjects()

        // Always: invalidate school day calculation caches (dictionary-based, no auto-eviction)
        invalidateSchoolDayCaches()

        // Notify ViewModels and other components so they can drop their own dictionary caches
        NotificationCenter.default.post(
            name: .memoryPressureDetected,
            object: nil,
            userInfo: ["level": level]
        )

        if level == .critical {
            // On critical pressure, also clear URLCache
            URLCache.shared.removeAllCachedResponses()
        }
    }
}

// MARK: - Environment Key

struct AppDependenciesKey: @preconcurrency EnvironmentKey {
    // Use the real, already-initialized stack from AppBootstrapping if available.
    // This prevents a second in-memory stack from being created during window restoration.
    @MainActor static let defaultValue: AppDependencies = {
        let stack = AppBootstrapping.getSharedCoreDataStack()
        return AppDependencies(coreDataStack: stack)
    }()
}

extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
