// MockNetworkMonitor.swift
// Mock implementation for network monitoring in tests

#if canImport(Testing)
import Foundation
import Network
@testable import Maria_s_Notebook

/// A mock network path that can be configured for testing
final class MockNetworkPath: @unchecked Sendable {
    var status: NWPath.Status

    init(status: NWPath.Status = .satisfied) {
        self.status = status
    }
}

/// Protocol for network monitoring to enable dependency injection
protocol NetworkMonitoring: AnyObject {
    var pathUpdateHandler: (@Sendable (NWPath) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
}

/// Extension to make NWPathMonitor conform to our protocol
extension NWPathMonitor: NetworkMonitoring {}

/// Mock network monitor for testing network state transitions
@Observable
@MainActor
final class MockNetworkMonitor {
    /// Current simulated network status
    var isNetworkAvailable: Bool = true

    /// Handlers to notify when network status changes
    private var statusChangeHandlers: [(Bool) -> Void] = []

    /// Simulate network becoming available
    func simulateNetworkAvailable() {
        isNetworkAvailable = true
        notifyHandlers()
    }

    /// Simulate network becoming unavailable
    func simulateNetworkUnavailable() {
        isNetworkAvailable = false
        notifyHandlers()
    }

    /// Add a handler for network status changes
    func onStatusChange(_ handler: @escaping (Bool) -> Void) {
        statusChangeHandlers.append(handler)
    }

    /// Remove all handlers
    func removeAllHandlers() {
        statusChangeHandlers.removeAll()
    }

    private func notifyHandlers() {
        for handler in statusChangeHandlers {
            handler(isNetworkAvailable)
        }
    }
}

/// Mock iCloud availability checker for testing
@Observable
@MainActor
final class MockICloudAvailability {
    /// Current simulated iCloud availability
    var isICloudAvailable: Bool = true

    /// Handlers to notify when iCloud status changes
    private var statusChangeHandlers: [(Bool) -> Void] = []

    /// Simulate iCloud becoming available (user signed in)
    func simulateICloudAvailable() {
        isICloudAvailable = true
        notifyHandlers()
    }

    /// Simulate iCloud becoming unavailable (user signed out)
    func simulateICloudUnavailable() {
        isICloudAvailable = false
        notifyHandlers()
    }

    /// Add a handler for iCloud status changes
    func onStatusChange(_ handler: @escaping (Bool) -> Void) {
        statusChangeHandlers.append(handler)
    }

    /// Remove all handlers
    func removeAllHandlers() {
        statusChangeHandlers.removeAll()
    }

    private func notifyHandlers() {
        for handler in statusChangeHandlers {
            handler(isICloudAvailable)
        }
    }
}
#endif
