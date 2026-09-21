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
/// struct CosmicDaybookApp: App {
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

    /// Started on first access; `CosmicDaybookApp+Startup` touches it once
    /// so monitoring begins at launch.
    @ObservationIgnored lazy var memoryPressureMonitor: MemoryPressureMonitor = {
        let monitor = MemoryPressureMonitor()
        monitor.startMonitoring { [weak self] level in
            self?.handleMemoryPressure(level: level)
        }
        return monitor
    }()

    // MARK: - Data Services

    // Work-related services
    // CDNote: WorkCompletionService is an enum with static methods,
    // access directly (e.g., WorkCompletionService.someMethod())

    // MARK: - Sync Services
    //
    // Both EventKit services are process-wide singletons: each owns the
    // `EKEventStore` change observer and the sync state the Today card
    // watches, so every reader must reach the same object. They are rebound
    // to this graph's store on each access so a prior Sample Class visit
    // cannot leave one pointed at that classroom's store. The comparison
    // keeps a read from a view body from mutating an observed property on
    // every evaluation. Views read them here, never through `.shared`.

    var reminderSync: ReminderSyncService {
        let service = ReminderSyncService.shared
        if service.managedObjectContext !== viewContext {
            service.managedObjectContext = viewContext
        }
        return service
    }

    var calendarSync: CalendarSyncService {
        let service = CalendarSyncService.shared
        if service.managedObjectContext !== viewContext {
            service.managedObjectContext = viewContext
        }
        return service
    }

    // MARK: - Backup Services (backing stores for AppDependencies+BackupServices.swift)
    //
    // Every lazy store below is `@ObservationIgnored`: it is set exactly once
    // and never replaced, so it is not view state. Tracking it would only add
    // registrar bookkeeping to every `dependencies.<service>` read in a body.
    // Extensions cannot declare stored properties, so the stores live here and
    // the extension accessors are plain reads of them.

    @ObservationIgnored lazy var _backupService = BackupService()
    @ObservationIgnored lazy var _backupTransactionManager = BackupTransactionManager()
    @ObservationIgnored lazy var _autoBackupManager = AutoBackupManager(coordinator: backupCoordinator)
    @ObservationIgnored lazy var _backupCoordinator = BackupCoordinator(
        backupService: _backupService,
        transactionManager: _backupTransactionManager,
        appRouter: appRouter
    )

    // MARK: - AI Services (backing stores for AppDependencies+AIServices.swift)

    @ObservationIgnored lazy var _aiRouter = AIClientRouter()
    @ObservationIgnored lazy var _chatService = ChatService(modelContext: viewContext, mcpClient: mcpClient)
    @ObservationIgnored lazy var _studentAnalysisService = StudentAnalysisService(
        modelContext: viewContext,
        mcpClient: mcpClient
    )
    @ObservationIgnored lazy var _reportGeneratorService = ReportGeneratorService()
    @ObservationIgnored lazy var _meetingInsightsService = MeetingInsightsService(
        modelContext: viewContext,
        mcpClient: mcpClient
    )
    @ObservationIgnored lazy var _monthlyReportDraftService = MonthlyReportDraftService(
        modelContext: viewContext,
        mcpClient: mcpClient,
        reportService: reportGeneratorService
    )

    // MARK: - UI Services

    /// The one toast service. Views reach it here (`dependencies.toastService`)
    /// so every toast goes through one access path; the singleton itself is
    /// for code that has no environment.
    var toastService: ToastService {
        ToastService.shared
    }

    // MARK: - Storage Services

    // PhotoStorageService is an enum with static methods, no initialization needed
    // Access methods directly via PhotoStorageService.methodName()

    /// The global "viewing year" lens shared by every screen.
    /// See Documentation/Implementation/SCHOOL_YEAR_SEPARATION.md.
    @ObservationIgnored lazy var schoolYearStore = SchoolYearStore()

    // MARK: - Presentation Services

    // Kept as an optional store rather than a lazy var: `handleMemoryPressure`
    // reads `_presentationsViewModel` directly to clear caches without creating
    // the view model, which a lazy accessor could not express.
    @ObservationIgnored private var _presentationsViewModel: PresentationsViewModel?
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

    /// The one instance the app configures at launch (`CosmicDaybookApp`
    /// calls `CloudKitSyncStatusService.shared.configure(with:)`). This used
    /// to lazily build a second, never-configured instance — each one starts
    /// its own `NWPathMonitor` and iCloud-account observer in `init`, so the
    /// first visit to Settings left a duplicate monitor running for the rest
    /// of the session, feeding a service that nothing else read.
    var cloudKitSyncStatusService: CloudKitSyncStatusService {
        CloudKitSyncStatusService.shared
    }

    @ObservationIgnored lazy var classroomSharingService = ClassroomSharingService(
        container: coreDataStack.container,
        context: viewContext,
        coreDataStack: coreDataStack
    )

    /// Singleton accessor for the observable shared-store zone repair
    /// service. Surfaces orphan counts and unrecoverable records to the
    /// UI so the lead guide can see when their data isn't syncing.
    var sharedStoreZoneRepair: SharedStoreZoneRepair {
        SharedStoreZoneRepair.shared
    }

    // MARK: - Router & Coordinators

    var appRouter: AppRouter {
        AppRouter.shared
    }

    @ObservationIgnored lazy var saveCoordinator = SaveCoordinator(toastService: toastService)

    @ObservationIgnored lazy var restoreCoordinator = RestoreCoordinator()

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
    /// Clears the shared school-day cache and bumps the data-version stamp that
    /// `SchoolCalendarService` and school-day-keyed views check. Called on
    /// memory pressure and whenever the underlying calendar data changes (a local
    /// edit or a CloudKit sync), so calendar-dependent counts never go stale.
    func invalidateSchoolDayCaches() {
        SchoolCalendarService.shared.invalidateCache()
        SchoolDayDataVersion.bump()
    }

    private func handleMemoryPressure(level: MemoryPressureLevel) {
        // Always: clear the in-memory image cache (NSCache).
        // NSCache auto-evicts under pressure, but an explicit call ensures it happens now.
        ImageCache.shared.removeAllObjects()

        // Always: invalidate school day calculation caches (dictionary-based, no auto-eviction)
        invalidateSchoolDayCaches()

        // Always: release the presentations view model's pinned object graph. Use the
        // backing field directly — the accessor would *create* the view model, which
        // is the opposite of what we want here.
        _presentationsViewModel?.clearCaches()

        // Notify ViewModels and other components so they can drop their own dictionary caches
        NotificationCenter.default.post(
            name: .memoryPressureDetected,
            object: nil,
            userInfo: ["level": level]
        )

        if level == .critical {
            // On critical pressure, also clear URLCache
            URLCache.shared.removeAllCachedResponses()

            // The search index is a full-corpus inverted index with no eviction
            // path — the single largest recoverable allocation. It rebuilds lazily
            // via `ensureReady()` the next time anything searches.
            SearchIndexService.shared.purge()

            // Finally, turn every registered managed object back into a fault.
            // The view context accumulates objects for the whole session and never
            // resets; this is the same call the backup deletion path already uses.
            viewContext.refreshAllObjects()
        }
    }
}

// MARK: - Environment Key

struct AppDependenciesKey: @preconcurrency EnvironmentKey {
    // Use the real, already-initialized stack from AppBootstrapping if available.
    // This prevents a second in-memory stack from being created during window restoration.
    static let defaultValue: AppDependencies = {
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
