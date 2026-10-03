import CoreData
import EventKit
import Foundation

/// State behind the Overview's "Needs your attention" list. Each input is read
/// once when the Overview appears (and the year-plan count again when the
/// roster or presentations change), never in `body`: the sharing count asks
/// iCloud about every classroom record, and the carried-over count is a fetch
/// per enrolled child. `SettingsAttention` decides which rows show.
@Observable @MainActor
final class SettingsDashboardViewModel {

    enum BackupRun: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    private(set) var lastBackup: Date?
    private(set) var unsharedClassroomRecords: Int?
    private(set) var carriedOverPlans: Int?
    private(set) var calendarAccessLost = false
    private(set) var remindersAccessLost = false
    private(set) var backupRun: BackupRun = .idle
    /// True once this notebook's very first backup succeeds here, for a small celebration.
    private(set) var madeFirstBackup = false

    /// When the Overview last asked about the share, and what it learned.
    private static var lastShareCheck: (at: Date, outside: Int?)?
    private static let shareCheckInterval: TimeInterval = 5 * 60

    private let dependencies: AppDependencies
    /// Reads and stamps the last-backup date the Backups card shows too.
    private let backupSettings: SettingsViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.backupSettings = SettingsViewModel(dependencies: dependencies)
    }

    /// The rows to show for iCloud's current health.
    func items(syncHealth: CloudKitHealthCheck.SyncHealth) -> [SettingsAttentionItem] {
        SettingsAttention.items(for: SettingsAttentionInputs(
            lastBackup: lastBackup,
            syncHealth: syncHealth,
            unsharedClassroomRecords: unsharedClassroomRecords,
            carriedOverPlans: carriedOverPlans,
            calendarAccessLost: calendarAccessLost,
            remindersAccessLost: remindersAccessLost
        ))
    }

    // MARK: - Reading

    /// The newer of the last backup made from the Backups card and the newest
    /// file in the backup folder, which automatic backups also write to.
    func refreshLastBackup() {
        let automatic = dependencies.backupCoordinator.backupStatus().mostRecentAutoBackupURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        lastBackup = [backupSettings.lastBackupDate, automatic].compactMap { $0 }.max()
    }

    /// Calendar or Reminders access that was on when the guide set it up and is off now.
    func refreshConnections(defaults: UserDefaults = .standard) {
        let calendars = defaults.array(forKey: UserDefaultsKeys.calendarSyncIdentifiers) as? [String] ?? []
        calendarAccessLost = SettingsAttention.accessLost(
            configured: !calendars.isEmpty,
            status: EKEventStore.authorizationStatus(for: .event)
        )
        remindersAccessLost = SettingsAttention.accessLost(
            configured: defaults.string(forKey: UserDefaultsKeys.reminderSyncListIdentifier) != nil,
            status: EKEventStore.authorizationStatus(for: .reminder)
        )
    }

    /// The same count the School year pane's Carried-over year plans button shows.
    func refreshCarriedOverPlans(context: NSManagedObjectContext, showTestStudents: Bool, testStudentNames: String) {
        carriedOverPlans = CarriedOverPlanSweepViewModel.badgeCount(
            context: context,
            showTestStudents: showTestStudents,
            testStudentNames: testStudentNames
        )
    }

    /// The Classroom pane's read-only "not in the share" count. Only the lead
    /// guide owns the records, and only once sharing is set up.
    func refreshUnsharedClassroomRecords(now: Date = Date()) async {
        // The check asks iCloud about the share and walks every classroom record,
        // so coming back to the Overview within a few minutes reuses the last answer.
        if let last = Self.lastShareCheck, now.timeIntervalSince(last.at) < Self.shareCheckInterval {
            unsharedClassroomRecords = last.outside
            return
        }
        defer { Self.lastShareCheck = (now, unsharedClassroomRecords) }
        let sharing = dependencies.classroomSharingService
        guard sharing.currentRole == .leadGuide else {
            unsharedClassroomRecords = nil
            return
        }
        await sharing.refreshShareInBackground()
        guard sharing.isSharing else {
            unsharedClassroomRecords = nil
            return
        }
        let contents = await ClassroomSharingService.shareContents(coreDataStack: dependencies.coreDataStack)
        unsharedClassroomRecords = contents?.outside
    }

    // MARK: - Backing Up

    /// Writes a backup into the backup folder, the same file Claude Desktop's
    /// create_backup writes: no save dialog, and never skipped for having no changes.
    func backUpNow(viewContext: NSManagedObjectContext) async {
        guard backupRun != .running else { return }
        backupRun = .running
        let result = await dependencies.autoBackupManager.performManualBackup(viewContext: viewContext)
        switch result {
        case .success(let date, _):
            backupSettings.setLastBackupNow()
            madeFirstBackup = lastBackup == nil
            lastBackup = date
            backupRun = .succeeded
        case .failure(_, let error):
            backupRun = .failed(AppErrorMessages.backupMessage(for: error, operation: "back up your notebook"))
        case .skippedNoChanges:
            backupRun = .idle
        }
    }
}
