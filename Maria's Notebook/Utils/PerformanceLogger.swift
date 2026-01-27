import Foundation
import OSLog

/// Performance logger for measuring SwiftData query performance and detecting main thread stutters.
/// Available in both Debug and Release builds.
enum PerformanceLogger {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook", category: "Performance")
    
    /// Measures the duration of a block and logs it with a screen name and item count.
    /// - Parameters:
    ///   - screenName: Name of the screen/component being measured
    ///   - itemCount: Number of items returned from the query
    ///   - operation: Block to measure
    /// - Returns: The result of the operation
    @discardableResult
    static func measure<T>(
        screenName: String,
        itemCount: Int? = nil,
        operation: () throws -> T
    ) rethrows -> T {
        let startTime = Date()
        let result = try operation()
        let duration = Date().timeIntervalSince(startTime)
        
        log(screenName: screenName, itemCount: itemCount, duration: duration)
        
        return result
    }
    
    /// Measures the duration of an async block and logs it with a screen name and item count.
    /// - Parameters:
    ///   - screenName: Name of the screen/component being measured
    ///   - itemCount: Number of items returned from the query
    ///   - operation: Async block to measure
    /// - Returns: The result of the operation
    @discardableResult
    static func measureAsync<T>(
        screenName: String,
        itemCount: Int? = nil,
        operation: () async throws -> T
    ) async rethrows -> T {
        let startTime = Date()
        let result = try await operation()
        let duration = Date().timeIntervalSince(startTime)
        
        log(screenName: screenName, itemCount: itemCount, duration: duration)
        
        return result
    }
    
    /// Logs performance metrics for a screen/operation.
    /// - Parameters:
    ///   - screenName: Name of the screen/component
    ///   - itemCount: Number of items (if applicable)
    ///   - duration: Duration in seconds
    static func log(screenName: String, itemCount: Int? = nil, duration: TimeInterval) {
        var message = "[Performance] \(screenName)"
        
        if let count = itemCount {
            message += " | Items: \(count)"
        }
        
        let ms = duration * 1000.0
        message += String(format: " | Duration: %.2f ms", ms)
        
        if ms > 100 {
            message += " ⚠️"
        }

        logger.info("\(message)")
        #if DEBUG
        print(message)
        #endif
    }

    /// Logs a screen's query results after @Query properties have loaded.
    /// - Parameters:
    ///   - screenName: Name of the screen/component
    ///   - itemCounts: Dictionary mapping query names to item counts
    static func logScreenLoad(screenName: String, itemCounts: [String: Int]) {
        var message = "[Performance] \(screenName) - Query Results:"
        for (queryName, count) in itemCounts.sorted(by: { $0.key < $1.key }) {
            message += "\n  • \(queryName): \(count)"
        }

        logger.info("\(message)")
        #if DEBUG
        print(message)
        #endif
    }

    /// Starts monitoring the main RunLoop for hangs/stutters.
    ///
    /// Note: Custom CFRunLoopObserver-based stutter detection was removed because it caused
    /// `_os_unfair_lock_recursive_abort` crashes when logging from within the run loop callback.
    ///
    /// For stutter detection, use Xcode's built-in tools instead:
    /// - Instruments > Time Profiler with "Record waiting threads"
    /// - Xcode Organizer > Hang Reports (from TestFlight/App Store users)
    /// - MetricKit for production hang metrics
    static func startStutterDetection() {
        // No-op: Use Xcode Instruments or MetricKit for stutter detection
    }
}


