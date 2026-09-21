import OSLog

nonisolated extension Logger {
    // MARK: - Core
    nonisolated static let app_ = Logger.app(category: "app")
    nonisolated static let cache = Logger.app(category: "cache")
    nonisolated static let database = Logger.app(category: "database")
    nonisolated static let ui = Logger.app(category: "ui")

    // MARK: - Data & Sync
    nonisolated static let backup = Logger.app(category: "backup")
    nonisolated static let sync = Logger.app(category: "sync")
    nonisolated static let migration = Logger.app(category: "migration")

    // MARK: - Features
    nonisolated static let attendance = Logger.app(category: "attendance")
    nonisolated static let lessons = Logger.app(category: "lessons")
    nonisolated static let albums = Logger.app(category: "albums")
    nonisolated static let students = Logger.app(category: "students")
    nonisolated static let work = Logger.app(category: "work")
    nonisolated static let presentations = Logger.app(category: "presentations")
    nonisolated static let planning = Logger.app(category: "planning")
    nonisolated static let projects = Logger.app(category: "projects")
    nonisolated static let notes = Logger.app(category: "notes")
    nonisolated static let reminders = Logger.app(category: "reminders")
    nonisolated static let todos = Logger.app(category: "todos")
    nonisolated static let inbox = Logger.app(category: "inbox")
    nonisolated static let settings = Logger.app(category: "settings")
    nonisolated static let community = Logger.app(category: "community")
    nonisolated static let schedules = Logger.app(category: "schedules")
    nonisolated static let issues = Logger.app(category: "issues")
    nonisolated static let resources = Logger.app(category: "resources")
    nonisolated static let stories = Logger.app(category: "stories")
    nonisolated static let bookClub = Logger.app(category: "bookClub")

    // MARK: - Services
    nonisolated static let ai = Logger.app(category: "ai")
    nonisolated static let photos = Logger.app(category: "photos")
    nonisolated static let reports = Logger.app(category: "reports")
    nonisolated static let calendar_ = Logger.app(category: "calendar")
    nonisolated static let lifecycle = Logger.app(category: "lifecycle")

    // MARK: - App lifecycle & infrastructure
    /// Category "App" — distinct from `app_`'s lowercase "app"; the name avoids
    /// colliding with the `app(category:)` factory.
    nonisolated static let appMain = Logger.app(category: "App")
    nonisolated static let bootstrapper = Logger.app(category: "Bootstrapper")
    nonisolated static let container = Logger.app(category: "Container")
    nonisolated static let startup = Logger.app(category: "Startup")
    nonisolated static let performance = Logger.app(category: "Performance")
    nonisolated static let energyPolicy = Logger.app(category: "EnergyPolicy")
    nonisolated static let toolbar = Logger.app(category: "Toolbar")
    nonisolated static let notebookCompanion = Logger.app(category: "NotebookCompanion")

    // MARK: - Core Data & store maintenance
    nonisolated static let coreDataStack = Logger.app(category: "CoreDataStack")
    nonisolated static let coreDataSchemaVersion = Logger.app(category: "CoreDataSchemaVersion")
    nonisolated static let coreDataPrimaryKeyRepair = Logger.app(category: "CoreDataPrimaryKeyRepair")
    nonisolated static let coreDataOrphanCleanup = Logger.app(category: "CoreDataOrphanCleanup")
    nonisolated static let databaseMaintenance = Logger.app(category: "DatabaseMaintenance")
    nonisolated static let deduplicationCoordinator = Logger.app(category: "DeduplicationCoordinator")
    nonisolated static let historyProcessor = Logger.app(category: "HistoryProcessor")
    nonisolated static let sharedStoreOrphanGuard = Logger.app(category: "SharedStoreOrphanGuard")
    nonisolated static let sharedStoreZoneRepair = Logger.app(category: "SharedStoreZoneRepair")

    // MARK: - CloudKit & sharing
    nonisolated static let cloudKit = Logger.app(category: "CloudKit")
    nonisolated static let cloudKitHealthCheck = Logger.app(category: "CloudKitHealthCheck")
    nonisolated static let cloudSharing = Logger.app(category: "CloudSharing")
    nonisolated static let classroomSharing = Logger.app(category: "ClassroomSharing")
    nonisolated static let classroomWorkspace = Logger.app(category: "ClassroomWorkspace")
    nonisolated static let syncedPreferences = Logger.app(category: "SyncedPreferences")

    // MARK: - Feature services
    nonisolated static let curriculumMap = Logger.app(category: "CurriculumMap")
    nonisolated static let parshaMetadataService = Logger.app(category: "ParshaMetadataService")
    nonisolated static let parshaSuggestionService = Logger.app(category: "ParshaSuggestionService")
    nonisolated static let searchIndex = Logger.app(category: "SearchIndex")
    nonisolated static let searchIndexSnapshot = Logger.app(category: "SearchIndexSnapshot")
    nonisolated static let sequenceAutoPopulate = Logger.app(category: "SequenceAutoPopulate")
    nonisolated static let spotlight = Logger.app(category: "Spotlight")
    nonisolated static let templateSeeder = Logger.app(category: "TemplateSeeder")
    nonisolated static let yearPlanPromotion = Logger.app(category: "YearPlanPromotion")
    nonisolated static let yearPlanRelease = Logger.app(category: "YearPlanRelease")

    // MARK: - MCP
    nonisolated static let mcpServer = Logger.app(category: "MCPServer")
    nonisolated static let mcpWriteJournal = Logger.app(category: "MCPWriteJournal")
}
