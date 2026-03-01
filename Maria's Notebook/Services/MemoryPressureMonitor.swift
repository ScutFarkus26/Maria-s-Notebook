import Foundation
import OSLog

private let logger = Logger.cache

/// Pressure level reported to the handler
enum MemoryPressureLevel {
    case warning
    case critical
}

/// Service for monitoring system memory pressure notifications.
///
/// Allows the app to proactively clear caches and reduce memory usage before the system terminates it.
/// Differentiates between `.warning` and `.critical` pressure levels and throttles responses
/// to avoid making pressure worse with expensive cleanup work.
@Observable
@MainActor
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

    // Throttle state — prevents rapid-fire cleanup from making pressure worse
    private var lastWarningResponse: Date = .distantPast
    private var lastCriticalResponse: Date = .distantPast
    private let warningThrottleInterval: TimeInterval = 30
    private let criticalThrottleInterval: TimeInterval = 5

    // MARK: - Initialization

    init() {
        // Monitor will be started when handler is set
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
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Read the actual event that fired via source.data (NOT source.mask)
                let event = DispatchSource.MemoryPressureEvent(rawValue: source.data)
                let now = Date()

                switch event {
                case .critical:
                    guard now.timeIntervalSince(self.lastCriticalResponse) >= self.criticalThrottleInterval else {
                        logger.debug("Critical memory pressure throttled")
                        return
                    }
                    self.lastCriticalResponse = now
                    self.lastPressureLevel = .critical

                    logger.warning("Critical memory pressure - clearing caches aggressively")

                    self.lastPressureEvent = now
                    self.pressureEventCount += 1
                    self.onPressureHandler?(.critical)

                case .warning:
                    guard now.timeIntervalSince(self.lastWarningResponse) >= self.warningThrottleInterval else {
                        logger.debug("Warning memory pressure throttled")
                        return
                    }
                    self.lastWarningResponse = now
                    self.lastPressureLevel = .warning

                    logger.info("Memory pressure warning - clearing non-essential caches")

                    self.lastPressureEvent = now
                    self.pressureEventCount += 1
                    self.onPressureHandler?(.warning)

                default:
                    break
                }
            }
        }

        source.resume()

        logger.info("Memory pressure monitoring started")
    }

    /// Stops monitoring memory pressure
    func stopMonitoring() {
        sourceHolder.source?.cancel()
        sourceHolder.source = nil
        onPressureHandler = nil
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Posted when the system reports memory pressure.
    /// `userInfo["level"]` contains the `MemoryPressureLevel`.
    static let memoryPressureDetected = Notification.Name("MemoryPressureDetected")
}
