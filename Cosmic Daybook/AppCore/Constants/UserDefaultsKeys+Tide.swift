import Foundation

// Keys for sharing to-dos with Tide (plan "Simplify the app", Phase 10).
// Device-local, Mac-only in use, never backed up or exported: the sharing
// runs from one Mac, and Tide's address itself is in the Keychain
// (`TideKeychain`). The Daybook Assistant doesn't compile this file.

nonisolated extension UserDefaultsKeys {
    /// Whether the notebook shares to-dos with Tide. Default off.
    static let tideSyncOn = "Tide.syncOn"
    /// The Tide list new notebook to-dos go to, by workspace path.
    static let tideDestinationFile = "Tide.destinationFile"
    /// The heading in that list they go under; absent for the list's first.
    static let tideDestinationHeading = "Tide.destinationHeading"
    /// The Tide lists whose to-dos show in the notebook, by workspace path;
    /// absent for every list of the area.
    static let tideShownLists = "Tide.shownLists"

    /// The linked to-dos (uuid string → true) both apps last agreed were
    /// open: the base a tick on either side is measured against, so an
    /// untick is never carried and a tick is carried once.
    static var tideLinkStates: String { CloudKitEnvironment.scoped("Tide.linkStates") }
    /// The linked to-dos (uuid strings) made from a Tide action, which follow
    /// Tide's words and due date.
    static var tideFromTide: String { CloudKitEnvironment.scoped("Tide.fromTide") }
    /// When Danny confirmed the first run's matches.
    static var tideFirstRunConfirmedAt: String { CloudKitEnvironment.scoped("Tide.firstRunConfirmedAt") }
    /// The notebook to-dos (uuid strings) the first run linked to a Tide action.
    static var tideFirstRunLinked: String { CloudKitEnvironment.scoped("Tide.firstRunLinked") }
    /// Linked to-dos (uuid string → their action's address) whose Tide action
    /// doesn't carry the notebook line, kept after a to-do is deleted so its
    /// action doesn't come back.
    static var tideUnmarkedLinks: String { CloudKitEnvironment.scoped("Tide.unmarkedLinks") }
    /// When the last sync with Tide finished.
    static var tideLastSyncAt: String { CloudKitEnvironment.scoped("Tide.lastSyncAt") }
}
