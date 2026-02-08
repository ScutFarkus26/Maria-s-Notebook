import Foundation
import Combine
import Network

/// Service responsible for monitoring network connectivity status
@MainActor
final class NetworkMonitoring: ObservableObject {
    // MARK: - Published State
    
    /// Whether network is available
    @Published private(set) var isNetworkAvailable: Bool = true
    
    // MARK: - Private State
    
    private var networkMonitor: NWPathMonitor?
    private let networkQueue = DispatchQueue(label: "com.mariasnotebook.networkmonitor")
    private var pendingNetworkTask: Task<Void, Never>?
    private var onNetworkChange: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        startNetworkMonitoring()
    }
    
    deinit {
        // Note: Cannot call stopNetworkMonitoring() from deinit since it's MainActor-isolated
        // The NWPathMonitor will be cleaned up when the object is deallocated
    }
    
    // MARK: - Public API
    
    /// Set a callback to be notified when network status changes
    func setNetworkChangeHandler(_ handler: @escaping (Bool) -> Void) {
        onNetworkChange = handler
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
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingNetworkTask?.cancel()
                self.pendingNetworkTask = Task { @MainActor [weak self] in
                    self?.handleNetworkChange(path)
                }
            }
        }
        networkMonitor?.start(queue: networkQueue)
    }
    
    private func handleNetworkChange(_ path: NWPath) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = path.status == .satisfied
        
        if wasAvailable != isNetworkAvailable {
            onNetworkChange?(isNetworkAvailable)
        }
    }
}
