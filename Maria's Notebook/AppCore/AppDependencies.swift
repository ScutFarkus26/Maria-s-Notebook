import Foundation
import SwiftData
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
///     let container: ModelContainer
///     let dependencies: AppDependencies
///
///     init() {
///         container = try! ModelContainer(for: AppSchema.self)
///         dependencies = AppDependencies(modelContext: container.mainContext)
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             RootView()
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
    let modelContext: ModelContext

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        let container = RepositoryContainer(context: modelContext, saveCoordinator: nil)
        _repositories = container
        return container
    }

    // MARK: - Data Services

    // Work-related services
    // Note: WorkCompletionService is an enum with static methods, access directly (e.g., WorkCompletionService.someMethod())

    // MARK: - Protocol-Based Services

    /// WorkCheckInService - Protocol-based architecture
    var workCheckInService: any WorkCheckInServiceProtocol {
        WorkCheckInServiceAdapter(context: modelContext)
    }

    /// WorkStepService - Protocol-based architecture
    var workStepService: any WorkStepServiceProtocol {
        WorkStepServiceAdapter(context: modelContext)
    }

    // Track services
    private var _groupTrackService: GroupTrackService?
    var groupTrackService: GroupTrackService {
        if let service = _groupTrackService {
            return service
        }
        let service = GroupTrackService()
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

    private var _groupTrackProgressResolver: GroupTrackProgressResolver?
    var groupTrackProgressResolver: GroupTrackProgressResolver {
        if let resolver = _groupTrackProgressResolver {
            return resolver
        }
        let resolver = GroupTrackProgressResolver()
        _groupTrackProgressResolver = resolver
        return resolver
    }

    // MARK: - Sync Services

    private var _reminderSyncService: ReminderSyncService?
    var reminderSync: ReminderSyncService {
        if let service = _reminderSyncService {
            return service
        }
        let service = ReminderSyncService.shared
        service.modelContext = modelContext
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
    var _selectiveRestoreService: SelectiveRestoreService?
    var _cloudBackupService: CloudBackupService?
    var _incrementalBackupService: IncrementalBackupService?
    var _backupSharingService: BackupSharingService?
    var _backupTransactionManager: BackupTransactionManager?
    var _selectiveExportService: SelectiveExportService?
    var _autoBackupManager: AutoBackupManager?

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
    var _databaseAnalysisService: DatabaseAnalysisService?
    var _reportGeneratorService: ReportGeneratorService?

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

    // MARK: - Preloading

    /// Preload presentations data in the background for instant navigation.
    /// Call this early in the app lifecycle (e.g., from RootView.onAppear) to warm up the cache.
    /// Safe to call - will silently fail if the database is not ready yet.
    /// - Parameters:
    ///   - inboxOrderRaw: Current inbox order preference
    ///   - missWindow: Current miss window setting
    ///   - showTestStudents: Whether to show test students
    ///   - testStudentNamesRaw: Test student names preference
    func preloadPresentationsData(
        calendar: Calendar,
        inboxOrderRaw: String,
        missWindow: PresentationsMissWindow,
        showTestStudents: Bool,
        testStudentNamesRaw: String
    ) {
        // Don't preload immediately - wait a moment for the database to initialize
        // This prevents crashes when accessing ModelContext too early in the app lifecycle
        Task { @MainActor in
            // Additional delay to ensure SwiftData is fully initialized
            // CloudKit initialization can take several seconds
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                Self.logger.warning("Failed to sleep for presentation preload: \(error)")
                return
            }

            // Safely update the presentations view model in the background
            // If this fails, it will be loaded normally when the user navigates to Presentations
            presentationsViewModel.update(
                modelContext: modelContext,
                calendar: calendar,
                inboxOrderRaw: inboxOrderRaw,
                missWindow: missWindow,
                showTestStudents: showTestStudents,
                testStudentNamesRaw: testStudentNamesRaw
            )
        }
    }

    // MARK: - Testing Support

    /// Create dependencies with in-memory storage for testing
    static func makeTest() throws -> AppDependencies {
        let schema = Schema([
            Student.self,
            Lesson.self,
            WorkModel.self,
            Note.self,
            // Add more models as needed for tests
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return AppDependencies(modelContext: container.mainContext)
    }

    /// Create dependencies with specific ModelContext for testing
    static func makeTest(context: ModelContext) -> AppDependencies {
        return AppDependencies(modelContext: context)
    }

    // MARK: - Memory Pressure Handling

    /// Called when system memory pressure is detected.
    /// Clears caches proportionally to the pressure level to avoid termination.
    private func handleMemoryPressure(level: MemoryPressureLevel) {
        // Always: clear the in-memory image cache (NSCache).
        // NSCache auto-evicts under pressure, but an explicit call ensures it happens now.
        ImageCache.shared.removeAllObjects()

        // Always: invalidate school day calculation caches (dictionary-based, no auto-eviction)
        SchoolDayCalculationCache.shared.invalidate()
        _schoolDayLookupCache?.invalidate()

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
    @MainActor static let defaultValue: AppDependencies = {
        // This should never be used in production - only for previews
        let schema = Schema([Student.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return AppDependencies(modelContext: container.mainContext)
        } catch {
            fatalError("Failed to create preview container: \(error.localizedDescription)")
        }
    }()
}

extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
