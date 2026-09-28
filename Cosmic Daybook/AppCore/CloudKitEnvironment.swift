import Foundation

/// The CloudKit environment this build syncs with, and what follows from it on
/// this device.
///
/// The notebook moves from CloudKit's Development environment to Production.
/// The two are separate databases with separate records, zones and user record
/// names, so a device keeps a separate copy of each: its own store files and
/// its own sync bookkeeping. One environment is active per build — the
/// `CLOUDKIT_ENVIRONMENT` build setting, which sets both the
/// `com.apple.developer.icloud-container-environment` entitlement (what
/// CloudKit obeys) and the `CloudKitEnvironment` Info.plist key read here (what
/// the app obeys). There is no switcher in the app.
///
/// Development keeps today's store files and key names exactly as they are, so
/// switching back to a Development build opens the untouched notebook.
nonisolated enum CloudKitEnvironment: String, Sendable, CaseIterable {
    case development = "Development"
    case production = "Production"

    static let infoPlistKey = "CloudKitEnvironment"

    /// This build's environment. Anything unreadable resolves to Development,
    /// the environment every build used before the key existed, never to
    /// Production.
    static let current: CloudKitEnvironment = resolve(
        Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
    )

    static func resolve(_ raw: String?) -> CloudKitEnvironment {
        raw.flatMap(Self.init(rawValue:)) ?? .development
    }

    /// Subfolder of the app's store directory that holds this environment's
    /// store files: none for Development (today's files stay where they are),
    /// `Production/` for Production.
    var storeSubdirectory: String? {
        self == .development ? nil : rawValue
    }

    /// The UserDefaults key for one environment's copy of a piece of sync
    /// state — history positions, the first-download gate, the sync event log.
    /// Read in the other environment, such a value describes a store this one
    /// doesn't have: a history token from the wrong store, or a gate that
    /// never opens. Development keeps the bare key.
    func scoped(_ key: String) -> String {
        self == .development ? key : "\(key).\(rawValue)"
    }

    static func scoped(_ key: String) -> String {
        current.scoped(key)
    }

    /// Apple allows `initializeCloudKitSchema` only in Development. A schema
    /// run in a Production build would fail at best; this build refuses it and
    /// says how to make a Development one instead.
    static var allowsSchemaInitialization: Bool {
        current == .development
    }
}
