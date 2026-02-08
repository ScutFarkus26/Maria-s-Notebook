import OSLog

extension Logger {
    static let cache = Logger.app(category: "cache")
    static let backup = Logger.app(category: "backup")
    static let sync = Logger.app(category: "sync")
    static let database = Logger.app(category: "database")
    static let ui = Logger.app(category: "ui")
}
