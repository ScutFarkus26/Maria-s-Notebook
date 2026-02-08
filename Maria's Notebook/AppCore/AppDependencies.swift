import Foundation
import SwiftData
import SwiftUI
import Combine

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
@MainActor
final class AppDependencies: ObservableObject {
    let modelContext: ModelContext
    
    // Required for ObservableObject conformance
    nonisolated let objectWillChange = ObservableObjectPublisher()
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Core Services
    
    private var _lifecycleService: LifecycleService?
    var lifecycleService: LifecycleService {
        if _lifecycleService == nil {
            _lifecycleService = LifecycleService()
        }
        return _lifecycleService!
    }
    
    // MARK: - Data Services
    
    // Work-related services
    // WorkCompletionService is an enum with static methods, no initialization needed
    var workCompletionService: WorkCompletionService {
        fatalError("WorkCompletionService is an enum with static methods, access directly")
    }
    
    private var _workCheckInService: WorkCheckInService?
    var workCheckInService: WorkCheckInService {
        if _workCheckInService == nil {
            _workCheckInService = WorkCheckInService(context: modelContext)
        }
        return _workCheckInService!
    }
    
    private var _workStepService: WorkStepService?
    var workStepService: WorkStepService {
        if _workStepService == nil {
            _workStepService = WorkStepService(context: modelContext)
        }
        return _workStepService!
    }
    
    // Track services
    private var _groupTrackService: GroupTrackService?
    var groupTrackService: GroupTrackService {
        if _groupTrackService == nil {
            _groupTrackService = GroupTrackService()
        }
        return _groupTrackService!
    }
    
    private var _trackProgressResolver: TrackProgressResolver?
    var trackProgressResolver: TrackProgressResolver {
        if _trackProgressResolver == nil {
            _trackProgressResolver = TrackProgressResolver()
        }
        return _trackProgressResolver!
    }
    
    private var _groupTrackProgressResolver: GroupTrackProgressResolver?
    var groupTrackProgressResolver: GroupTrackProgressResolver {
        if _groupTrackProgressResolver == nil {
            _groupTrackProgressResolver = GroupTrackProgressResolver()
        }
        return _groupTrackProgressResolver!
    }
    
    // MARK: - Sync Services
    
    private var _reminderSyncService: ReminderSyncService?
    var reminderSync: ReminderSyncService {
        if _reminderSyncService == nil {
            _reminderSyncService = ReminderSyncService.shared
            _reminderSyncService?.modelContext = modelContext
        }
        return _reminderSyncService!
    }
    
    private var _calendarSyncService: CalendarSyncService?
    var calendarSync: CalendarSyncService {
        if _calendarSyncService == nil {
            _calendarSyncService = CalendarSyncService()
        }
        return _calendarSyncService!
    }
    
    // MARK: - Backup Services
    
    private var _backupService: BackupService?
    var backupService: BackupService {
        if _backupService == nil {
            _backupService = BackupService()
        }
        return _backupService!
    }
    
    private var _selectiveRestoreService: SelectiveRestoreService?
    var selectiveRestoreService: SelectiveRestoreService {
        if _selectiveRestoreService == nil {
            _selectiveRestoreService = SelectiveRestoreService(backupService: backupService)
        }
        return _selectiveRestoreService!
    }
    
    private var _cloudBackupService: CloudBackupService?
    var cloudBackupService: CloudBackupService {
        if _cloudBackupService == nil {
            _cloudBackupService = CloudBackupService(backupService: backupService)
        }
        return _cloudBackupService!
    }
    
    private var _incrementalBackupService: IncrementalBackupService?
    var incrementalBackupService: IncrementalBackupService {
        if _incrementalBackupService == nil {
            _incrementalBackupService = IncrementalBackupService(backupService: backupService)
        }
        return _incrementalBackupService!
    }
    
    private var _backupSharingService: BackupSharingService?
    var backupSharingService: BackupSharingService {
        if _backupSharingService == nil {
            _backupSharingService = BackupSharingService(backupService: backupService)
        }
        return _backupSharingService!
    }
    
    private var _backupTransactionManager: BackupTransactionManager?
    var backupTransactionManager: BackupTransactionManager {
        if _backupTransactionManager == nil {
            _backupTransactionManager = BackupTransactionManager(backupService: backupService)
        }
        return _backupTransactionManager!
    }
    
    private var _selectiveExportService: SelectiveExportService?
    var selectiveExportService: SelectiveExportService {
        if _selectiveExportService == nil {
            _selectiveExportService = SelectiveExportService(backupService: backupService)
        }
        return _selectiveExportService!
    }
    
    private var _autoBackupManager: AutoBackupManager?
    var autoBackupManager: AutoBackupManager {
        if _autoBackupManager == nil {
            _autoBackupManager = AutoBackupManager(backupService: backupService)
        }
        return _autoBackupManager!
    }
    
    // MARK: - Migration Services
    
    private var _dataMigrations: DataMigrations.Type?
    var dataMigrations: DataMigrations.Type {
        return DataMigrations.self
    }
    
    // MARK: - Business Logic Services
    
    private var _followUpInboxEngine: FollowUpInboxEngine?
    var followUpInboxEngine: FollowUpInboxEngine {
        if _followUpInboxEngine == nil {
            _followUpInboxEngine = FollowUpInboxEngine()
        }
        return _followUpInboxEngine!
    }
    
    private var _reportGeneratorService: ReportGeneratorService?
    var reportGeneratorService: ReportGeneratorService {
        if _reportGeneratorService == nil {
            _reportGeneratorService = ReportGeneratorService()
        }
        return _reportGeneratorService!
    }
    
    // MARK: - UI Services
    
    private var _toastService: ToastService?
    var toastService: ToastService {
        if _toastService == nil {
            _toastService = ToastService.shared
        }
        return _toastService!
    }
    
    // MARK: - Storage Services
    
    // PhotoStorageService is an enum with static methods, no initialization needed
    // Access methods directly via PhotoStorageService.methodName()
    
    // MARK: - Calendar Services
    
    private var _schoolCalendarService: SchoolCalendarService?
    var schoolCalendarService: SchoolCalendarService {
        if _schoolCalendarService == nil {
            _schoolCalendarService = SchoolCalendarService.shared
        }
        return _schoolCalendarService!
    }
    
    private var _schoolDayLookupCache: SchoolDayLookupCache?
    var schoolDayLookupCache: SchoolDayLookupCache {
        if _schoolDayLookupCache == nil {
            _schoolDayLookupCache = SchoolDayLookupCache()
        }
        return _schoolDayLookupCache!
    }
    
    // MARK: - Presentation Services
    
    private var _presentationsViewModel: PresentationsViewModel?
    var presentationsViewModel: PresentationsViewModel {
        if _presentationsViewModel == nil {
            _presentationsViewModel = PresentationsViewModel()
        }
        return _presentationsViewModel!
    }
    
    // MARK: - CloudKit Services
    
    // CloudKitConfigurationService is an enum with static methods, no initialization needed
    // Access methods directly via CloudKitConfigurationService.methodName()
    
    private var _cloudKitSyncStatusService: CloudKitSyncStatusService?
    var cloudKitSyncStatusService: CloudKitSyncStatusService {
        if _cloudKitSyncStatusService == nil {
            _cloudKitSyncStatusService = CloudKitSyncStatusService()
        }
        return _cloudKitSyncStatusService!
    }
    
    // MARK: - Router & Coordinators
    
    private var _appRouter: AppRouter?
    var appRouter: AppRouter {
        if _appRouter == nil {
            _appRouter = AppRouter.shared
        }
        return _appRouter!
    }
    
    private var _saveCoordinator: SaveCoordinator?
    var saveCoordinator: SaveCoordinator {
        if _saveCoordinator == nil {
            _saveCoordinator = SaveCoordinator()
        }
        return _saveCoordinator!
    }
    
    private var _restoreCoordinator: RestoreCoordinator?
    var restoreCoordinator: RestoreCoordinator {
        if _restoreCoordinator == nil {
            _restoreCoordinator = RestoreCoordinator()
        }
        return _restoreCoordinator!
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
            try? await Task.sleep(for: .seconds(1))
            
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
    static func makeTest() -> AppDependencies {
        let schema = Schema([
            Student.self,
            Lesson.self,
            WorkModel.self,
            Note.self,
            // Add more models as needed for tests
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return AppDependencies(modelContext: container.mainContext)
    }
    
    /// Create dependencies with specific ModelContext for testing
    static func makeTest(context: ModelContext) -> AppDependencies {
        return AppDependencies(modelContext: context)
    }
}

// MARK: - Environment Key

struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue: AppDependencies = {
        // This should never be used in production - only for previews
        let schema = Schema([Student.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return AppDependencies(modelContext: container.mainContext)
    }()
}

extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}

// MARK: - Phase 4 Migration Notes

/*
 Phase 4 Migration Strategy:
 
 1. Add all remaining services to this container (target: 118+ services)
 2. Replace singleton calls with dependency access:
    - ReminderSyncService.shared → dependencies.reminderSync
    - AppRouter.shared → dependencies.appRouter
 
 3. Update ViewModels to accept dependencies via initializer:
    - TodayViewModel(dependencies: AppDependencies)
    - InboxSheetViewModel(dependencies: AppDependencies)
 
 4. Services should be protocols for testing:
    protocol WorkLifecycleService { ... }
    class WorkLifecycleServiceImpl: WorkLifecycleService { ... }
 
 5. Circular dependencies (identified in Phase 1.2 docs):
    - Break with protocols
    - Use weak references where appropriate
    - Consider event bus for loose coupling
 */
