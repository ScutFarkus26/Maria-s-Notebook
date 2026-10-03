import Foundation
import OSLog
import Darwin
#if os(iOS)
import UIKit
#endif

nonisolated private let logger = Logger.cache

/// Current process resident memory footprint in megabytes, or nil if the
/// kernel query failed. Used to enrich memory-pressure log lines so the
/// next investigation doesn't have to guess at process state.
private func currentMemoryFootprintMB() -> Double? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return Double(info.phys_footprint) / (1024.0 * 1024.0)
}

/// Pressure level reported to the handler
nonisolated enum MemoryPressureLevel {
    case warning
    case critical
}

/// Service for monitoring system memory pressure notifications.
///
/// Allows the app to proactively clear caches and reduce memory usage before the system terminates it.
/// Differentiates between `.warning` and `.critical` pressure levels and throttles responses
/// to avoid making pressure worse with expensive cleanup work.
///
/// Two sources feed it: the dispatch memory-pressure source on both platforms and, on iOS,
/// UIKit's memory warning. Both go through `respond(to:from:)`, so a warning that reaches
/// the app both ways inside one throttle window clears the caches once.
@Observable
final class MemoryPressureMonitor {

    // MARK: - State

    private(set) var lastPressureEvent: Date?
    private(set) var lastPressureLevel: MemoryPressureLevel?
    private(set) var pressureEventCount: Int = 0

    // MARK: - Private State

    // Store source in a holder class that can be cleaned up from deinit
    private class SourceHolder {
        var source: DispatchSourceMemoryPressure?

        deinit {
            source?.cancel()
        }
    }

    private let sourceHolder = SourceHolder()
    private var onPressureHandler: ((MemoryPressureLevel) -> Void)?

    /// Where UIKit's memory warning is observed: the default center in the
    /// app, a private one in tests.
    private let notificationCenter: NotificationCenter
    /// The clock the throttle reads; tests advance their own.
    private let now: () -> Date
    #if os(iOS)
    @ObservationIgnored private var memoryWarningObservation: NotificationCenter.ObservationToken?
    #endif

    // Throttle state — prevents rapid-fire cleanup from making pressure worse
    private var lastWarningResponse: Date = .distantPast
    private var lastCriticalResponse: Date = .distantPast
    private let warningThrottleInterval: TimeInterval = 30
    private let criticalThrottleInterval: TimeInterval = 5

    // MARK: - Initialization

    init(notificationCenter: NotificationCenter = .default, now: @escaping () -> Date = { Date() }) {
        // Monitor will be started when handler is set
        self.notificationCenter = notificationCenter
        self.now = now
    }

    // MARK: - Public API

    /// Starts monitoring memory pressure with a callback handler.
    /// The handler receives the pressure level so callers can respond proportionally.
    func startMonitoring(onPressure: @escaping @MainActor (MemoryPressureLevel) -> Void) {
        // Stop any existing monitoring
        stopMonitoring()

        self.onPressureHandler = onPressure

        // Create memory pressure source
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        sourceHolder.source = source

        source.setEventHandler { [weak self] in
            // The event that fired is `source.data` (NOT `source.mask`), which
            // Dispatch defines only inside this handler: read it here and carry
            // the value into the hop to the main actor.
            let event = DispatchSource.MemoryPressureEvent(rawValue: source.data)
            guard let level = MemoryPressureMonitor.level(for: event) else { return }
            Task { @MainActor [weak self] in
                self?.respond(to: level, from: "dispatch")
            }
        }

        source.resume()

        #if os(iOS)
        // UIKit's memory warning is the signal Apple names for iOS apps
        // ("Responding to low-memory warnings"). It takes the dispatch
        // warning's path: same throttle, same caches, same log line.
        memoryWarningObservation = notificationCenter.addObserver(
            of: UIApplication.self,
            for: .didReceiveMemoryWarning
        ) { [weak self] _ in
            self?.respond(to: .warning, from: "UIKit")
        }
        #endif

        logger.info("Memory pressure monitoring started")
    }

    /// Stops monitoring memory pressure
    func stopMonitoring() {
        sourceHolder.source?.cancel()
        sourceHolder.source = nil
        #if os(iOS)
        if let memoryWarningObservation {
            notificationCenter.removeObserver(memoryWarningObservation)
            self.memoryWarningObservation = nil
        }
        #endif
        onPressureHandler = nil
    }

    /// The level a dispatch memory-pressure event stands for: critical when
    /// it contains `.critical`, else warning when it contains `.warning`,
    /// else nil (the source asks only for these two). Dispatch can merge
    /// events that arrive before the handler runs into one value such as
    /// `[.warning, .critical]`, so this tests membership, never equality.
    nonisolated static func level(for event: DispatchSource.MemoryPressureEvent) -> MemoryPressureLevel? {
        if event.contains(.critical) { return .critical }
        if event.contains(.warning) { return .warning }
        return nil
    }

    /// The process footprint for a log line ("123.4 MB", or "unknown"); the
    /// idle trim (`AppDependencies.trimIdleMemory`) logs it too.
    static var footprintDescription: String {
        currentMemoryFootprintMB().map { String(format: "%.1f MB", $0) } ?? "unknown"
    }

    // MARK: - Response

    /// One pressure event, from either source: throttled per level, logged
    /// with the footprint, then handed to the handler.
    private func respond(to level: MemoryPressureLevel, from source: String) {
        let time = now()
        switch level {
        case .critical:
            guard time.timeIntervalSince(lastCriticalResponse) >= criticalThrottleInterval else {
                logger.debug("Critical memory pressure throttled")
                return
            }
            lastCriticalResponse = time
            let criticalMsg = "Critical memory pressure - clearing caches aggressively " +
                "(source: \(source), footprint: \(Self.footprintDescription), event #\(pressureEventCount + 1))"
            logger.warning("\(criticalMsg, privacy: .public)")

        case .warning:
            guard time.timeIntervalSince(lastWarningResponse) >= warningThrottleInterval else {
                logger.debug("Warning memory pressure throttled")
                return
            }
            lastWarningResponse = time
            let warningMsg = "Memory pressure warning - clearing non-essential caches " +
                "(source: \(source), footprint: \(Self.footprintDescription), event #\(pressureEventCount + 1))"
            logger.info("\(warningMsg, privacy: .public)")
        }

        lastPressureLevel = level
        lastPressureEvent = time
        pressureEventCount += 1
        onPressureHandler?(level)
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Posted when the system reports memory pressure.
    /// `userInfo["level"]` contains the `MemoryPressureLevel`.
    static let memoryPressureDetected = Notification.Name("MemoryPressureDetected")
}
