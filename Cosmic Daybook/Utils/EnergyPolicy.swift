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
//
// Deferred work waits for the device to cool rather than giving up and
// running hot: `waitUntilMaintenanceAllowed()` suspends until the policy
// flips back. The power source adds a second, softer answer (`profile`):
// on external power the app can afford routine work more often than on
// battery, e.g. the iPad's background backup gap.

import Foundation
import OSLog
#if os(iOS)
import UIKit
#elseif os(macOS)
import IOKit.ps
#endif

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
        /// Charging, full on the charger, or a Mac on AC. Unknown (the
        /// simulator) reads as battery, the cautious answer.
        var isOnExternalPower: Bool = false

        @MainActor
        static var current: Inputs {
            let info = ProcessInfo.processInfo
            return Inputs(
                thermalState: info.thermalState,
                isLowPowerModeEnabled: info.isLowPowerModeEnabled,
                isOnExternalPower: PowerSource.isExternal
            )
        }
    }

    /// How much routine work the device can afford right now.
    nonisolated enum Profile: String, Sendable {
        /// Hot or Low Power Mode: discretionary work waits.
        case constrained
        /// Cool, running on battery: routine work at its normal cadence.
        case battery
        /// Cool and plugged in: routine work can run more often.
        case externalPower
    }

    // MARK: - State

    /// The readings the current answer is based on. Observable so a future
    /// Settings row can show why maintenance is paused.
    private(set) var inputs: Inputs

    /// True while discretionary background work should stand down.
    var shouldDeferMaintenance: Bool { Self.shouldDefer(inputs) }

    /// Constrained, battery, or external power (see `Profile`).
    var profile: Profile { Self.profile(for: inputs) }

    /// Tasks suspended in `waitUntilMaintenanceAllowed()`, resumed when the
    /// policy stops deferring (or when their task is cancelled).
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

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
        // Enable battery monitoring before the first read, or iOS reports
        // `.unknown` and the first profile is wrongly "battery".
        PowerSource.startMonitoring()
        self.inputs = .current
        self.tracksSystem = true
        startObserving()
    }

    /// Test seam: a policy pinned to fixed readings, with no system observers.
    init(thermalState: ProcessInfo.ThermalState, isLowPowerMode: Bool, isOnExternalPower: Bool = false) {
        self.inputs = Inputs(
            thermalState: thermalState,
            isLowPowerModeEnabled: isLowPowerMode,
            isOnExternalPower: isOnExternalPower
        )
        self.tracksSystem = false
    }

    /// Test seam: moves a pinned policy to new readings, exactly as a system
    /// notification would move the shared one (waiters resume on a flip).
    func simulate(_ newInputs: Inputs) {
        apply(newInputs)
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

    /// Pure form of the profile, so it can be pinned without an instance.
    nonisolated static func profile(for inputs: Inputs) -> Profile {
        if shouldDefer(inputs) { return .constrained }
        return inputs.isOnExternalPower ? .externalPower : .battery
    }

    // MARK: - Waiting

    /// Suspends until discretionary work is allowed again: returns at once on
    /// a cool device, otherwise when the device cools down or Low Power Mode
    /// is turned off. Never gives up and runs hot. Returns early (with
    /// `Task.isCancelled` set) if the calling task is cancelled, so callers
    /// should check cancellation afterwards.
    func waitUntilMaintenanceAllowed() async {
        guard shouldDeferMaintenance, !Task.isCancelled else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if shouldDeferMaintenance, !Task.isCancelled {
                    waiters[id] = continuation
                } else {
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.waiters.removeValue(forKey: id)?.resume()
            }
        }
    }

    /// Number of tasks currently suspended in `waitUntilMaintenanceAllowed()`.
    var waitingTaskCount: Int { waiters.count }

    // MARK: - Private

    private func startObserving() {
        let center = NotificationCenter.default
        var names: [Notification.Name] = [
            ProcessInfo.thermalStateDidChangeNotification,
            .NSProcessInfoPowerStateDidChange,
            PowerSource.didChangeNotification
        ]
        #if os(iOS)
        names.append(UIDevice.batteryStateDidChangeNotification)
        #endif
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
        apply(.current)
    }

    private func apply(_ latest: Inputs) {
        guard latest != inputs else { return }
        let previousProfile = profile
        let wasDeferring = shouldDeferMaintenance
        inputs = latest
        if previousProfile != profile {
            let detail = "thermal=\(latest.thermalState.energyPolicyName) "
                + "lowPower=\(latest.isLowPowerModeEnabled) externalPower=\(latest.isOnExternalPower)"
            Self.logger.notice("Energy profile \(self.profile.rawValue, privacy: .public): \(detail, privacy: .public)")
        }
        guard wasDeferring, !shouldDeferMaintenance else { return }
        let resumed = waiters
        waiters.removeAll()
        for continuation in resumed.values { continuation.resume() }
    }
}

// MARK: - Power source

/// Reads whether the device is running on external power, and posts
/// `didChangeNotification` when that changes.
private enum PowerSource {
    nonisolated static let didChangeNotification = Notification.Name("EnergyPolicy.powerSourceDidChange")

    #if os(iOS)
    @MainActor static var isExternal: Bool {
        switch UIDevice.current.batteryState {
        case .charging, .full: return true
        case .unplugged, .unknown: return false
        @unknown default: return false
        }
    }

    /// Battery monitoring is off by default and `batteryState` reads
    /// `.unknown` until it is enabled; the monitoring itself is free.
    @MainActor static func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    #elseif os(macOS)
    @MainActor static var isExternal: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return true
        }
        // A Mac with no battery reports AC; a laptop reports its battery.
        return (type as String) == kIOPMACPowerKey
    }

    @MainActor private static var runLoopSource: CFRunLoopSource?

    /// IOKit calls back on the main run loop whenever the power source or
    /// charge changes; it is relayed as a notification the policy observes.
    @MainActor static func startMonitoring() {
        guard runLoopSource == nil,
              let source = IOPSNotificationCreateRunLoopSource({ _ in
                  NotificationCenter.default.post(name: PowerSource.didChangeNotification, object: nil)
              }, nil)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }
    #else
    @MainActor static var isExternal: Bool { false }
    @MainActor static func startMonitoring() {}
    #endif
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
