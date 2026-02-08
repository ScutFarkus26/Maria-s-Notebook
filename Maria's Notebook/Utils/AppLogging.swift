import OSLog

extension Logger {
    static let cache = Logger(subsystem: "com.mariasnotebook", category: "cache")
    static let backup = Logger(subsystem: "com.mariasnotebook", category: "backup")
    static let sync = Logger(subsystem: "com.mariasnotebook", category: "sync")
    static let database = Logger(subsystem: "com.mariasnotebook", category: "database")
    static let ui = Logger(subsystem: "com.mariasnotebook", category: "ui")
}
