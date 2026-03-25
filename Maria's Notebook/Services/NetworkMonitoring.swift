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
    
    private var networkMonitor: NWPathMonitor?
    private var pendingNetworkTask: Task<Void, Never>?
    private var networkChangeContinuation: AsyncStream<Bool>.Continuation?
    
    // MARK: - Initialization
    
    init() {
        startNetworkMonitoring()
    }
    
    deinit {
        // Note: Cannot call stopNetworkMonitoring() from deinit since it's MainActor-isolated
        // The NWPathMonitor will be cleaned up when the object is deallocated
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
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.networkChangeContinuation = nil
                }
            }
        }
    }
    
    /// Stop network monitoring
    func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
        pendingNetworkTask?.cancel()
        pendingNetworkTask = nil
    }
    
    // MARK: - Private Methods
    
    private func startNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { @Sendable [weak self] path in
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
        networkMonitor?.start(queue: .global(qos: .utility))
    }
    
    private func handleNetworkChange(_ path: NWPath) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = path.status == .satisfied
        
        if wasAvailable != isNetworkAvailable {
            networkChangeContinuation?.yield(isNetworkAvailable)
        }
    }
}
