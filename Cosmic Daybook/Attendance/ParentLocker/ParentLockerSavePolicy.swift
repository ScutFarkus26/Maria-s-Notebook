import Foundation

/// Whether this build may change anything in ParentLocker (plan "ParentLocker
/// attendance", Safety while building). Debug builds and test runs only read:
/// they load the rosters, match the children and show what they would send,
/// but never save a mark, never record a ParentLocker send and never write a
/// match. Only Release and TestFlight builds save. Why:
/// - A macOS test run launches the real app on the live store.
/// - A Debug build's send record would silence the 9:00 reminder and switch
///   every Release device into live updates.
/// - A Debug build may be reading stale data.
///
/// Its own ProcessInfo check, since `AppBootstrapping` isn't in the Daybook
/// Assistant. Sync tests pass `.live` with a fake transport, so they check
/// real saving.
nonisolated enum ParentLockerSavePolicy: Sendable, Equatable {
    /// Saves marks, records sends and writes matches.
    case live
    /// Reads and plans only.
    case previewOnly

    /// This process's policy: `.previewOnly` in a Debug build or a test run.
    static let current = resolve(isDebugBuild: isDebugBuild, environment: ProcessInfo.processInfo.environment)

    static func resolve(isDebugBuild: Bool, environment: [String: String]) -> ParentLockerSavePolicy {
        if isDebugBuild || environment["XCTestConfigurationFilePath"] != nil { return .previewOnly }
        return .live
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    var allowsSaving: Bool { self == .live }
}
