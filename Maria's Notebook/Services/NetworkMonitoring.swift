import Foundation
import Network

/// Service responsible for monitoring network connectivity status
@Observable
@MainActor
final class NetworkMonitoring {
    // MARK: - State
    
    /// Whether network is available
    private(set) var isNetworkAvailable: Bool = true
    
    // MARK: - Private State
    
    /// `NWPathMonitor` is retained by Network.framework once started, so it
    /// is not released by ARC — it has to be cancelled. A `@MainActor` deinit
    /// can't touch isolated state, so the monitor lives in a non-isolated
    /// holder whose own deinit cancels it (same pattern as
    /// `MemoryPressureMonitor.SourceHolder`).
    private final class MonitorHolder: @unchecked Sendable {
        var monitor: NWPathMonitor?

        deinit {
            monitor?.cancel()
        }
    }

    private let monitorHolder = MonitorHolder()
    private var pendingNetworkTask: Task<Void, Never>?
    private var networkChangeContinuation: AsyncStream<Bool>.Continuation?
    
    // MARK: - Initialization
    
    init() {
        startNetworkMonitoring()
    }
    
    // MARK: - Public API
    
    /// Observe network status changes as an AsyncStream
    func observeNetworkChanges() -> AsyncStream<Bool> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            networkChangeContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.networkChangeContinuation = nil
                }
            }
        }
    }

    // MARK: - Private Methods
    
    private func startNetworkMonitoring() {
        let networkMonitor = NWPathMonitor()
        monitorHolder.monitor = networkMonitor
        networkMonitor.pathUpdateHandler = { @Sendable [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingNetworkTask?.cancel()
                self.pendingNetworkTask = Task { @MainActor [weak self] in
                    self?.handleNetworkChange(path)
                }
            }
        }
        // Use global utility queue instead of custom DispatchQueue
        // This leverages Swift concurrency's cooperative thread pool
        networkMonitor.start(queue: .global(qos: .utility))
    }
    
    private func handleNetworkChange(_ path: NWPath) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = path.status == .satisfied
        
        if wasAvailable != isNetworkAvailable {
            networkChangeContinuation?.yield(isNetworkAvailable)
        }
    }
}
