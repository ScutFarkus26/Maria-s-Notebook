import OSLog

extension Logger {
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

    // MARK: - Services
    nonisolated static let ai = Logger.app(category: "ai")
    nonisolated static let photos = Logger.app(category: "photos")
    nonisolated static let reports = Logger.app(category: "reports")
    nonisolated static let calendar_ = Logger.app(category: "calendar")
    nonisolated static let lifecycle = Logger.app(category: "lifecycle")
}
