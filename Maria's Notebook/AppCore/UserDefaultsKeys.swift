import Foundation

/// Centralized UserDefaults keys to prevent typos and improve maintainability.
/// All keys should be defined here and referenced via this enum.
enum UserDefaultsKeys {
    // MARK: - App Core
    static let useInMemoryStoreOnce = "UseInMemoryStoreOnce"
    static let ephemeralSessionFlag = "SwiftDataEphemeralSession"
    static let lastStoreErrorDescription = "SwiftDataLastErrorDescription"
    static let allowLocalStoreFallback = "AllowLocalStoreFallback"
    static let enableCloudKitSync = "EnableCloudKitSync"
    static let cloudKitActive = "CloudKitActive"
    static let cloudKitLastErrorDescription = "CloudKitLastErrorDescription"
    static let cloudKitLastSuccessfulSyncDate = "CloudKitSync.lastSuccessfulSyncDate"
    static let cloudKitLastSyncError = "CloudKitSync.lastSyncError"

    // MARK: - Planning
    static let planningRootViewMode = "PlanningRootView.mode"
    static let planningInboxOrder = "PlanningInbox.order"
    
    // MARK: - Backup
    static let backupEncrypt = "Backup.encrypt"
    static let backupEncryptDefault = "Backup.encryptDefault"  // True = encryption on by default
    static let backupAllowChecksumBypass = "Backup.allowChecksumBypass"
    static let lastBackupTimeInterval = "lastBackupTimeInterval"

    // MARK: - Cloud Backup
    static let cloudBackupScheduleEnabled = "CloudBackup.scheduleEnabled"
    static let cloudBackupScheduleIntervalHours = "CloudBackup.scheduleIntervalHours"
    static let cloudBackupScheduleRetentionCount = "CloudBackup.scheduleRetentionCount"
    static let cloudBackupLastDate = "CloudBackup.lastBackupDate"

    // MARK: - Auto Backup
    static let autoBackupEnabled = "AutoBackup.enabled"
    static let autoBackupRetentionCount = "AutoBackup.retentionCount"
    static let autoBackupScheduledEnabled = "AutoBackup.scheduledEnabled"
    static let autoBackupIntervalHours = "AutoBackup.intervalHours"
    static let autoBackupLastScheduledDate = "AutoBackup.lastScheduledDate"

    // MARK: - Incremental Backup
    static let incrementalBackupLastDate = "IncrementalBackup.lastDate"
    static let incrementalBackupLastID = "IncrementalBackup.lastID"

    // MARK: - Backup Integrity
    static let backupIntegrityAutoVerifyEnabled = "BackupIntegrity.autoVerifyEnabled"
    static let backupIntegrityWarningDaysThreshold = "BackupIntegrity.warningDaysThreshold"

    // MARK: - Backup Notifications
    static let backupNotificationsEnabled = "BackupNotifications.enabled"
    static let backupNotificationsShowSuccess = "BackupNotifications.showSuccess"
    static let backupNotificationsShowFailure = "BackupNotifications.showFailure"
    static let backupNotificationsShowHealthWarnings = "BackupNotifications.showHealthWarnings"
    
    // MARK: - Attendance
    static let attendanceEmailEnabled = "AttendanceEmail.enabled"
    static let attendanceEmailTo = "AttendanceEmail.to"
    static let attendanceEmailFrom = "AttendanceEmail.from"
    // Dynamic keys: "Attendance.locked.<yyyy-MM-dd>"
    
    // MARK: - Lesson Age
    static let lessonAgeWarningDays = "LessonAge.warningDays"
    static let lessonAgeOverdueDays = "LessonAge.overdueDays"
    static let lessonAgeFreshColorHex = "LessonAge.freshColorHex"
    static let lessonAgeWarningColorHex = "LessonAge.warningColorHex"
    static let lessonAgeOverdueColorHex = "LessonAge.overdueColorHex"
    
    // MARK: - Work Age
    static let workAgeWarningDays = "WorkAge.warningDays"
    static let workAgeOverdueDays = "WorkAge.overdueDays"
    static let workAgeFreshColorHex = "WorkAge.freshColorHex"
    static let workAgeWarningColorHex = "WorkAge.warningColorHex"
    static let workAgeOverdueColorHex = "WorkAge.overdueColorHex"
    
    // MARK: - General
    static let generalShowTestStudents = "General.showTestStudents"
    static let generalTestStudentNames = "General.testStudentNames"
    
    // MARK: - Reminder Sync
    static let reminderSyncSyncListName = "ReminderSync.syncListName"
    
    // MARK: - Debug
    static let debugSimulateDatabaseInitFailure = "DEBUG_SimulateDatabaseInitFailure"
    
    // MARK: - Migrations
    static let hasUnifiedNotesMigrationRun = "Migration.unifiedNotes.v1"
}




