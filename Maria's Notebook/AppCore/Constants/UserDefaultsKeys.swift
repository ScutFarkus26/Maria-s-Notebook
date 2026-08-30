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
    static let cloudKitErrorLog = "cloudKitErrorLog"
    static let persistentHistoryLastToken = "PersistentHistory.lastToken"
    static let persistentHistoryLastPurgeDate = "PersistentHistory.lastPurgeDate"
    static let cloudKitLastSuccessfulExportStartDate = "CloudKitSync.lastSuccessfulExportStartDate"

    // MARK: - Planning
    static let planningRootViewMode = "PlanningRootView.mode"
    static let planningInboxOrder = "PlanningInbox.order"
    
    // MARK: - Backup
    static let backupEncrypt = "Backup.encrypt"
    static let lastBackupTimeInterval = "lastBackupTimeInterval"

    // MARK: - Auto Backup
    static let autoBackupEnabled = "AutoBackup.enabled"
    static let autoBackupRetentionCount = "AutoBackup.retentionCount"
    static let autoBackupScheduledEnabled = "AutoBackup.scheduledEnabled"
    static let autoBackupIntervalHours = "AutoBackup.intervalHours"

    // MARK: - Attendance
    static let attendanceEmailEnabled = "AttendanceEmail.enabled"
    static let attendanceEmailTo = "AttendanceEmail.to"
    static let attendanceEmailFrom = "AttendanceEmail.from"
    static let attendanceEmailNameOrder = "AttendanceEmail.nameOrder"
    static let attendanceEmailGroupByLevel = "AttendanceEmail.groupByLevel"
    // Dynamic keys: "Attendance.locked.<yyyy-MM-dd>"
    
    // MARK: - CDLesson Age
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
    
    // MARK: - Debug
    static let debugSimulateDatabaseInitFailure = "DEBUG_SimulateDatabaseInitFailure"
    
    // MARK: - Todos
    static let todoTagOrder = "Todo.tagOrder"
    static let todoHideCompleted = "Todo.hideCompleted"

    // MARK: - AI Models (per-area)
    static let aiModelChat = "AI.chatModel"
    static let aiModelLessonPlanning = "AI.lessonPlanningModel"
    static let aiModelBackgroundTasks = "AI.backgroundTasksModel"
    /// Off by default: automatic mode must not move student records from the
    /// device to Private Cloud Compute without an explicit school choice.
    static let aiAllowAutomaticPrivateCloud = "AI.allowAutomaticPrivateCloud"
    /// Off by default: exposing notebook data to MCP clients (Claude
    /// Desktop) is an explicit teacher choice. macOS only.
    static let aiMCPServerEnabled = "AI.mcpServerEnabled"

    // MARK: - Parent Reports

    static let parentReportsReminderEnabled = "ParentReports.reminderEnabled"

    // MARK: - CDLesson Planning
    static let lessonPlanningModel = "LessonPlanning.model"
    static let lessonPlanningTimeout = "LessonPlanning.timeout"
    static let lessonPlanningSystemPrompt = "LessonPlanning.systemPrompt"
    static let lessonPlanningDefaultDepth = "LessonPlanning.defaultDepth"
    static let lessonPlanningTemperature = "LessonPlanning.temperature"

    // MARK: - Presentations
    static let presentationHistoryNameDisplayStyle = "PresentationHistory.nameDisplayStyle"
    static let lessonsAgendaStartDate = "LessonsAgenda.startDate"
    static let lessonsAgendaMissWindow = "LessonsAgenda.missWindow"
    static let planningRecentWindowDays = "Planning.recentWindowDays"
    /// Legacy — the "Work" checkbox on the old presentations-only calendar.
    /// Read once by `CalendarKindFilter.migratedFromLegacyToggles`, never written.
    static let presentationsCalendarShowWork = "PresentationsCalendar.showWork"
    /// What the merged calendar shows: a `CalendarKindFilter` raw value.
    static let calendarVisibleKinds = "Calendar.visibleKinds"

    // MARK: - Quick CDNote Button
    static let quickNoteButtonOffsetX = "QuickNoteButton.offsetX"
    static let quickNoteButtonOffsetY = "QuickNoteButton.offsetY"
    static let notebookCompanionVisible = "NotebookCompanion.visible"
    static let notebookCompanionDetached = "NotebookCompanion.detached"
    static let notebookCompanionHasDesktopPosition = "NotebookCompanion.hasDesktopPosition"
    static let notebookCompanionDesktopX = "NotebookCompanion.desktopX"
    static let notebookCompanionDesktopY = "NotebookCompanion.desktopY"

    // MARK: - Lessons
    static let lessonsSortIndexMigrated = "Lessons.sortIndexMigrated"

    // MARK: - Students
    static let studentDetailViewActiveTab = "StudentDetailView.activeTab"
    static let meetingsWorkflowDaysSinceThreshold = "MeetingsWorkflow.daysSinceThreshold"
    static let studentsViewSortOrder = "StudentsView.sortOrder"
    static let studentsViewSelectedFilter = "StudentsView.selectedFilter"
    static let studentsViewStyle = "StudentsView.viewStyle"
    static let studentPickerSortOrder = "StudentPicker.sortOrder"

    // MARK: - Checklist
    static let checklistSelectedArea = "Checklist.selectedArea"

    // MARK: - Logs
    static let logsMenuRootViewMode = "LogsMenuRootView.mode"

    // MARK: - Work
    static let workAgendaHideScheduled = "WorkAgenda.hideScheduled"
    static let workAgendaVisibleKinds = "WorkAgenda.visibleKinds"
    /// Widens the Attention list to every open work item — the list that used
    /// to be a separate Children Working destination.
    static let workAgendaShowAllOpenWork = "WorkAgenda.showAllOpenWork"
    /// Whether the Scheduled calendar pane is open beneath the list it is
    /// scheduled from. Collapsing it hands the whole screen back to the list.
    static let workAgendaCalendarExpanded = "WorkAgenda.calendarExpanded"
    /// The calendar pane's share of the workspace height, 0.2–0.7.
    static let workAgendaCalendarFraction = "WorkAgenda.calendarFraction"
    /// Legacy — the "Presentations" checkbox on the old work-only calendar.
    /// Read once by `CalendarKindFilter.migratedFromLegacyToggles`, never written.
    static let workCalendarShowPresentations = "WorkCalendar.showPresentations"

    // MARK: - Migrations
    static let pdfFolderMigrationV1Complete = "Migration.pdfFolder.v1"
    static let classroomStoreMigrationV1Complete = "ClassroomStoreMigration.v1.completed"
    static let attendanceNoteLinkBackfillV1Complete = "AttendanceNoteLinkBackfill.v1.completed"

    // MARK: - Shared Store Sync Repair
    static let sharedStoreZoneRepairLastTimeoutAt = "SharedStoreZoneRepair.lastTimeoutAt"

    /// One-shot flag the user sets via Settings → Database → "Reset Local
    /// Cache". On the next launch, `CoreDataStack.init` checks this flag,
    /// deletes the on-disk stores (along with their WAL/SHM siblings and
    /// related migration/sharing flags), then clears it. The container then
    /// reconstitutes from CloudKit. Used to recover from corrupt persistent
    /// history that prevents `NSCloudKitMirroringDelegate` from initializing.
    static let resetLocalCacheOnLaunch = "AppCore.resetLocalCacheOnLaunch"
    static let resetLocalCacheArmedAt = "AppCore.resetLocalCacheArmedAt"
    static let resetLocalCacheArmedSource = "AppCore.resetLocalCacheArmedSource"

    // MARK: - Today
    static let todayDayPadExpanded = "Today.dayPadExpanded"
    static let todayDoneTodayExpanded = "Today.doneTodayExpanded"
    /// Dynamic per-date keys for dismissable Today cards: "Today.dayCardDismissed.<yyyy-MM-dd>.<cardName>"
    static let todayDayCardDismissedPrefix = "Today.dayCardDismissed."

    // MARK: - School Year
    /// Month (1–12) the school year starts on. Default September.
    static let schoolYearStartMonth = "SchoolYear.startMonth"
    /// Day (1–31) the school year starts on. Default 1.
    static let schoolYearStartDay = "SchoolYear.startDay"
    /// Persisted active viewing lens token ("all", "year:2025", "cycle:2025").
    static let schoolYearSelection = "SchoolYear.selection"
    /// Date (as `timeIntervalSinceReferenceDate`) every elapsed-day counter counts from.
    /// Absent means counters run over the full history. See `SchoolYearCounters`.
    static let schoolYearCounterEpoch = "SchoolYear.counterEpoch"
    /// Begin year of the last school year whose "start counters fresh?" prompt was answered,
    /// so the prompt appears once per school year.
    static let schoolYearCounterPromptAnsweredYear = "SchoolYear.counterPromptAnsweredYear"

    // MARK: - Recall
    /// Days after a lesson's last recall (or mastery) before it becomes due for a spaced
    /// re-check. Default 90.
    static let recallSpacedIntervalDays = "Recall.spacedIntervalDays"

    // MARK: - Albums
    /// Security-scoped bookmarks ([Data]) for the folders holding the guide's
    /// teaching-album PDFs. The PDFs stay where they live; the app only reads them.
    static let albumsFolderBookmarks = "Albums.folderBookmarks"
    /// Album filename → file modification date at last open, for "Updated" badges.
    static let albumsLastSeenModDates = "Albums.lastSeenModDates"
    /// Scene-restoration key for the Albums section's sidebar selection.
    static let albumsSidebarSelection = "Albums.selection"
    /// Content fingerprint → album filename, recorded at each load. Lets
    /// `AlbumIdentityRepair` recognise a renamed or moved PDF and carry the
    /// guide's bookmarks, notes, highlights, and ink across to the new name.
    static let albumsFingerprints = "Albums.fingerprints"
}
