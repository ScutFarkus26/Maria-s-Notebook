import Foundation

/// Centralized UserDefaults keys to prevent typos and improve maintainability.
/// All keys should be defined here and referenced via this enum.
nonisolated enum UserDefaultsKeys {
    // Keys written through `CloudKitEnvironment.scoped` describe one CloudKit
    // environment's notebook — its history positions, first download, sync
    // log, user record name — so the Development and Production copies on one
    // device never read each other's. Development keeps the bare key.

    // MARK: - App Core
    static let useInMemoryStoreOnce = "UseInMemoryStoreOnce"
    static let ephemeralSessionFlag = "SwiftDataEphemeralSession"
    static let lastStoreErrorDescription = "SwiftDataLastErrorDescription"
    static let allowLocalStoreFallback = "AllowLocalStoreFallback"
    static let enableCloudKitSync = "EnableCloudKitSync"
    static let cloudKitActive = "CloudKitActive"
    static let cloudKitLastErrorDescription = "CloudKitLastErrorDescription"
    static var cloudKitLastSuccessfulSyncDate: String {
        CloudKitEnvironment.scoped("CloudKitSync.lastSuccessfulSyncDate")
    }
    static let cloudKitLastSyncError = "CloudKitSync.lastSyncError"
    static var cloudKitErrorLog: String { CloudKitEnvironment.scoped("cloudKitErrorLog") }
    /// Legacy — the history processor's single token for both stores, which
    /// only ever held a position in one of them. Removed on launch.
    static let persistentHistoryLastToken = "PersistentHistory.lastToken"
    /// The history processor's position in each store: archived
    /// `NSPersistentHistoryToken` data keyed by `NSPersistentStore.identifier`.
    static var persistentHistoryStoreTokens: String { CloudKitEnvironment.scoped("PersistentHistory.storeTokens") }
    static var persistentHistoryLastPurgeDate: String { CloudKitEnvironment.scoped("PersistentHistory.lastPurgeDate") }
    static var cloudKitLastSuccessfulExportStartDate: String {
        CloudKitEnvironment.scoped("CloudKitSync.lastSuccessfulExportStartDate")
    }

    // MARK: - Planning
    static let planningRootViewMode = "PlanningRootView.mode"
    static let planningInboxOrder = "PlanningInbox.order"
    
    // MARK: - Backup
    static let lastBackupTimeInterval = "lastBackupTimeInterval"

    // MARK: - Auto Backup
    static let autoBackupEnabled = "AutoBackup.enabled"
    static let autoBackupRetentionCount = "AutoBackup.retentionCount"
    static let autoBackupScheduledEnabled = "AutoBackup.scheduledEnabled"
    static let autoBackupIntervalHours = "AutoBackup.intervalHours"
    /// `timeIntervalSinceReferenceDate` of the last scheduled auto-backup run.
    static let autoBackupLastScheduledDate = "AutoBackup.lastScheduledDate"
    static let autoBackupLastBackgroundDate = "AutoBackup.lastBackgroundDate"
    /// Whether backups carry the note photos (format v28). Default on.
    static let backupIncludesNotePhotos = "Backup.includesNotePhotos"

    // MARK: - Attendance
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

    // MARK: - AI
    /// Off by default: the app's AI must not move student records from the
    /// device to Private Cloud Compute without an explicit school choice.
    static let aiAllowAutomaticPrivateCloud = "AI.allowAutomaticPrivateCloud"
    /// Off by default: exposing notebook data to MCP clients (Claude
    /// Desktop) is an explicit teacher choice. macOS only.
    static let aiMCPServerEnabled = "AI.mcpServerEnabled"

    // MARK: - Parent Reports

    static let parentReportsReminderEnabled = "ParentReports.reminderEnabled"

    // MARK: - CDLesson Planning
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
    /// No longer read (its one-time migration was never wired up); still carried in backups.
    static let presentationsCalendarShowWork = "PresentationsCalendar.showWork"
    /// What the merged calendar shows: a `CalendarKindFilter` raw value.
    static let calendarVisibleKinds = "Calendar.visibleKinds"

    // MARK: - Quick CDNote Button
    static let quickNoteButtonOffsetX = "QuickNoteButton.offsetX"
    static let quickNoteButtonOffsetY = "QuickNoteButton.offsetY"
    static let quickCaptureButtonVisible = "QuickCaptureButton.visible"

    // MARK: - Lessons
    /// The guide's hand-ordered curriculum areas, oldest spelling of the key.
    static let lessonsAreaOrder = "Lessons.AreaOrder"
    /// Which spine the Lessons map is grouped by (a `MapSpine` raw value).
    static let lessonsMapSpine = "Lessons.mapSpine"

    // MARK: - Students
    static let studentDetailViewActiveTab = "StudentDetailView.activeTab"
    static let meetingsWorkflowDaysSinceThreshold = "MeetingsWorkflow.daysSinceThreshold"
    static let meetingsWorkflowRequeuedStudents = "MeetingsWorkflow.requeuedStudents"
    static let studentsViewSortOrder = "StudentsView.sortOrder"
    static let studentsViewSelectedFilter = "StudentsView.selectedFilter"
    static let studentsViewStyle = "StudentsView.viewStyle"
    static let studentPickerSortOrder = "StudentPicker.sortOrder"

    // MARK: - Onboarding
    static let hasCompletedOnboarding = "hasCompletedOnboarding"

    // MARK: - Settings
    /// Last-opened settings category (a `SettingsCategory` raw value).
    static let settingsSelectedCategory = "settings_selectedCategory"
    /// Version whose "What's New" banner the guide has already dismissed.
    static let whatsNewDismissedVersion = "WhatsNew.dismissedVersion"

    // MARK: - Resources
    /// Grid or list on the resource library (a `ResourceViewMode` raw value).
    static let resourceLibraryViewMode = "resourceLibrary.viewMode"

    // MARK: - Planning Calendar
    static let planningCalendarShowTodos = "PlanningCalendar.showTodos"
    static let planningCalendarShowParsha = "PlanningCalendar.showParsha"
    static let planningCalendarShowNotes = "PlanningCalendar.showNotes"
    static let planningCalendarShowHolidays = "PlanningCalendar.showHolidays"
    static let planningCalendarShowEvents = "PlanningCalendar.showEvents"

    // MARK: - Calendar & Reminder Sync
    static let calendarSyncIdentifiers = "CalendarSync.syncCalendarIdentifiers"
    static let calendarSyncNames = "CalendarSync.syncCalendarNames"
    /// Single-calendar spellings kept only so an old install migrates forward.
    static let calendarSyncLegacyIdentifier = "CalendarSync.syncCalendarIdentifier"
    static let calendarSyncLegacyName = "CalendarSync.syncCalendarName"
    static let reminderSyncListIdentifier = "ReminderSync.syncListIdentifier"
    static let reminderSyncListName = "ReminderSync.syncListName"

    // MARK: - Checklist
    static let checklistSelectedArea = "Checklist.selectedArea"

    // MARK: - Logs
    static let logsMenuRootViewMode = "LogsMenuRootView.mode"

    // MARK: - Work
    static let workAgendaHideScheduled = "WorkAgenda.hideScheduled"
    static let workAgendaVisibleKinds = "WorkAgenda.visibleKinds"
    /// Whether the Scheduled calendar pane is open beneath the list it is
    /// scheduled from. Collapsing it hands the whole screen back to the list.
    static let workAgendaCalendarExpanded = "WorkAgenda.calendarExpanded"
    /// The calendar pane's share of the workspace height, 0.2–0.7.
    static let workAgendaCalendarFraction = "WorkAgenda.calendarFraction"
    /// Legacy — the "Presentations" checkbox on the old work-only calendar.
    /// No longer read (its one-time migration was never wired up); still carried in backups.
    static let workCalendarShowPresentations = "WorkCalendar.showPresentations"

    // MARK: - Migrations
    static let retiredAIKeysRemovedV1 = "Migration.retiredAIKeysRemoved.v1"

    // MARK: - Classroom Sharing
    static var classroomIdentityRecordName: String { CloudKitEnvironment.scoped("ClassroomIdentity.userRecordName") }
    static let classroomIdentityDisplayName = "ClassroomIdentity.displayName"
    /// URIs of classroom records this device created before the classroom
    /// share's pin arrived, waiting to be attached (`SharedStoreOrphanGuard`).
    /// Device-local; never exported.
    static var classroomSharePendingAttach: String {
        CloudKitEnvironment.scoped("ClassroomShare.pendingAttach")
    }
    /// Set while a fresh private store is still receiving its first download
    /// from iCloud (see `FirstDownloadGate`). Device-local; never exported.
    static var firstDownloadPending: String { CloudKitEnvironment.scoped("CloudKit.firstDownloadPending") }

    /// One-shot flag the user sets via Settings → Database → "Reset Local
    /// Cache". On the next launch, `CoreDataStack.init` checks this flag,
    /// deletes the on-disk stores (along with their WAL/SHM siblings and
    /// related migration/sharing flags), then clears it. The container then
    /// reconstitutes from CloudKit. Used to recover from corrupt persistent
    /// history that prevents `NSCloudKitMirroringDelegate` from initializing.
    static let resetLocalCacheOnLaunch = "AppCore.resetLocalCacheOnLaunch"

    /// Set after the first launch-time check-in link repair on this device.
    /// Orphaned check-ins are only deleted from the second run on, so a fresh
    /// install still importing its work rows from CloudKit deletes nothing.
    static var checkInLinkRepairHasRun: String { CloudKitEnvironment.scoped("DataMigrations.checkInLinkRepair.hasRun") }
    static let resetLocalCacheArmedAt = "AppCore.resetLocalCacheArmedAt"
    static let resetLocalCacheArmedSource = "AppCore.resetLocalCacheArmedSource"

    // MARK: - Today
    static let todayDayPadExpanded = "Today.dayPadExpanded"
    static let todayDoneTodayExpanded = "Today.doneTodayExpanded"
    /// Whether the undated ("Anytime") reminders are disclosed on Today.
    /// Default closed: the standing pile of undated Apple Reminders belongs
    /// in reach, not on the fold.
    static let todayAnytimeRemindersExpanded = "Today.anytimeRemindersExpanded"
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
    /// Begin year of the last school year whose carried-over year-plan sweep was run.
    /// Only drops the count badge in Settings — the button itself always stays.
    static let yearPlanCarryOverSweepYear = "YearPlan.carryOverSweepYear"

    // MARK: - Recall
    /// Days after a lesson's last recall (or mastery) before it becomes due for a spaced
    /// re-check. Default 90.
    static let recallSpacedIntervalDays = "Recall.spacedIntervalDays"

    // MARK: - Three-Year View
    /// Days without a presentation before an area is flagged "untouched" on a
    /// child's Three-Year View. Default 90.
    static let curriculumMapUntouchedDays = "CurriculumMap.untouchedDays"
    /// Per-area overrides of the above: `[area: days]`, because Art and Parsha have
    /// different rhythms than Math.
    static let curriculumMapUntouchedDaysByArea = "CurriculumMap.untouchedDaysByArea"
    /// Last zoom chosen on the per-child grid (`CurriculumZoom` raw value).
    static let curriculumMapZoom = "CurriculumMap.zoom"
    /// Whether the grids show key lessons only or every lesson
    /// (`CurriculumGranularity` raw value).
    static let curriculumMapGranularity = "CurriculumMap.granularity"

    // MARK: - Sidebar
    /// Dynamic per-group keys for the macOS sidebar's collapsed/expanded
    /// state: "Sidebar.expanded.<NavigationGroup.ID raw value>".
    static let sidebarGroupExpandedPrefix = "Sidebar.expanded."
    static func sidebarGroupExpanded(_ groupID: String) -> String {
        sidebarGroupExpandedPrefix + groupID
    }

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
