import Foundation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook", category: "MemoryPressure")

/// Service for monitoring system memory pressure notifications
/// Allows the app to proactively clear caches and reduce memory usage before the system terminates it
@Observable
@MainActor
final class MemoryPressureMonitor {
    
    // MARK: - State
    
    private(set) var lastPressureEvent: Date?
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
    private var onPressureHandler: (() -> Void)?
    
    // MARK: - Initialization
    
    init() {
        // Monitor will be started when handler is set
    }
    
    // MARK: - Public API
    
    /// Starts monitoring memory pressure with a callback handler
    /// - Parameter onPressure: Closure to call when memory pressure is detected
    func startMonitoring(onPressure: @escaping @MainActor () -> Void) {
        // Stop any existing monitoring
        stopMonitoring()
        
        self.onPressureHandler = onPressure
        
        // Create memory pressure source
        sourceHolder.source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        
        sourceHolder.source?.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                logger.warning("Memory pressure detected - clearing caches")
                
                self.lastPressureEvent = Date()
                self.pressureEventCount += 1
                
                // Call the handler on main actor
                self.onPressureHandler?()
            }
        }
        
        sourceHolder.source?.resume()
        
        logger.info("Memory pressure monitoring started")
    }
    
    /// Stops monitoring memory pressure
    func stopMonitoring() {
        sourceHolder.source?.cancel()
        sourceHolder.source = nil
        onPressureHandler = nil
    }
}
