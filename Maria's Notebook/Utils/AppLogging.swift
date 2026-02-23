import OSLog

extension Logger {
    nonisolated static let cache = Logger.app(category: "cache")
    nonisolated static let backup = Logger.app(category: "backup")
    nonisolated static let sync = Logger.app(category: "sync")
    nonisolated static let database = Logger.app(category: "database")
    nonisolated static let ui = Logger.app(category: "ui")
}
