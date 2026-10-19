// TideSyncPolicy.swift
// Which copies of the notebook may talk to Tide.

import Foundation

/// Where this copy of the notebook may share to-dos with Tide: only the Mac
/// app, and only a Release build outside a test run. Tide's server is on
/// Danny's Mac, and a simulator reaches the Mac's `localhost`, so a Debug
/// build or a test talking to it would change his real to-dos
/// (`ParentLockerSavePolicy` is the same rule for the school's site).
nonisolated enum TideSyncPolicy: Equatable, Sendable {
    case live
    case notOnThisDevice
    case testCopy

    static let current = resolve(
        isMac: isMac, isDebugBuild: isDebugBuild, environment: ProcessInfo.processInfo.environment
    )

    static func resolve(isMac: Bool, isDebugBuild: Bool, environment: [String: String]) -> TideSyncPolicy {
        guard isMac else { return .notOnThisDevice }
        if isDebugBuild || environment["XCTestConfigurationFilePath"] != nil { return .testCopy }
        return .live
    }

    private static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
