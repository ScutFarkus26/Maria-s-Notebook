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
            _selectiveRestoreService = SelectiveRestoreService()
        }
        return _selectiveRestoreService!
    }
    
    private var _cloudBackupService: CloudBackupService?
    var cloudBackupService: CloudBackupService {
        if _cloudBackupService == nil {
            _cloudBackupService = CloudBackupService()
        }
        return _cloudBackupService!
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
