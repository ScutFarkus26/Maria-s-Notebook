// EnergyPolicy.swift
// One answer to "is now a bad time to do discretionary work?".
//
// Apple's guidance is to defer maintenance when the device is thermally
// stressed (`.serious` and above) or the user has asked for Low Power Mode.
// Everything the app runs on its own initiative — post-import deduplication,
// shared-store zone repair, album indexing, the search and Spotlight index
// rebuilds, scheduled backups — consults this before starting.
//
// User-initiated work (Sync Now, Repair Sync Errors, a manual backup, a
// search) is never gated: the guide asked for it, so it runs hot or not.

import Foundation
import OSLog

@MainActor
@Observable
final class EnergyPolicy {

    /// The app-wide policy, fed by the real `ProcessInfo` notifications.
    static let shared = EnergyPolicy()

    nonisolated private static let logger = Logger.energyPolicy

    // MARK: - Inputs

    /// The two system readings the policy is derived from. Kept as a value
    /// type so tests can pin them without touching the real `ProcessInfo`.
    nonisolated struct Inputs: Sendable, Equatable {
        var thermalState: ProcessInfo.ThermalState
        var isLowPowerModeEnabled: Bool

        static var current: Inputs {
            let info = ProcessInfo.processInfo
            return Inputs(
                thermalState: info.thermalState,
                isLowPowerModeEnabled: info.isLowPowerModeEnabled
            )
        }
    }

    // MARK: - State

    /// The readings the current answer is based on. Observable so a future
    /// Settings row can show why maintenance is paused.
    private(set) var inputs: Inputs

    /// True while discretionary background work should stand down.
    var shouldDeferMaintenance: Bool { Self.shouldDefer(inputs) }

    /// Whether this instance follows the live system readings. False for the
    /// pinned instances tests build.
    private let tracksSystem: Bool

    // MARK: - Observers

    /// `NotificationCenter.addObserver(forName:…)` hands back a token that has
    /// to be removed by hand; a `@MainActor deinit` can't touch isolated
    /// state, so the tokens live in a non-isolated holder whose own deinit
    /// removes them (same pattern as `NetworkMonitoring.MonitorHolder`).
    private final class ObserverHolder: @unchecked Sendable {
        /// `NSObjectProtocol` is not `Sendable`, and the holder's own `deinit`
        /// is nonisolated. Safe because the tokens are opaque handles: they are
        /// written once from the main actor at construction and only ever read
        /// again by `deinit`, which by definition has no other references left.
        nonisolated(unsafe) var tokens: [any NSObjectProtocol] = []

        deinit {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    private let observerHolder = ObserverHolder()

    // MARK: - Initialization

    private init() {
        self.inputs = .current
        self.tracksSystem = true
        startObserving()
    }

    /// Test seam: a policy pinned to fixed readings, with no system observers.
    init(thermalState: ProcessInfo.ThermalState, isLowPowerMode: Bool) {
        self.inputs = Inputs(thermalState: thermalState, isLowPowerModeEnabled: isLowPowerMode)
        self.tracksSystem = false
    }

    // MARK: - Policy

    /// Pure form of the rule, so the boolean can be pinned without an instance.
    nonisolated static func shouldDefer(_ inputs: Inputs) -> Bool {
        if inputs.isLowPowerModeEnabled { return true }
        switch inputs.thermalState {
        case .serious, .critical:
            return true
        case .nominal, .fair:
            return false
        @unknown default:
            // An unfamiliar state is not a reason to stop working.
            return false
        }
    }

    // MARK: - Private

    private func startObserving() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            ProcessInfo.thermalStateDidChangeNotification,
            .NSProcessInfoPowerStateDidChange
        ]
        observerHolder.tokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshFromSystem()
                }
            }
        }
    }

    private func refreshFromSystem() {
        guard tracksSystem else { return }
        let latest = Inputs.current
        guard latest != inputs else { return }
        let wasDeferring = shouldDeferMaintenance
        inputs = latest
        guard wasDeferring != shouldDeferMaintenance else { return }
        let state = shouldDeferMaintenance ? "deferring" : "resuming"
        let detail = "thermal=\(latest.thermalState.energyPolicyName) lowPower=\(latest.isLowPowerModeEnabled)"
        Self.logger.notice("Background maintenance \(state, privacy: .public): \(detail, privacy: .public)")
    }
}

nonisolated extension ProcessInfo.ThermalState {
    /// Log-friendly name; `ThermalState` has no `CustomStringConvertible`.
    var energyPolicyName: String {
        switch self {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
