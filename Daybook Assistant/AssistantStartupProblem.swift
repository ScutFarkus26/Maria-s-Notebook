import Foundation

/// What the "Can't start" screen says when the class won't open on this
/// iPhone.
///
/// The store errors are shared with the notebook and speak its language
/// ("a newer version of Cosmic Daybook", "Settings → Database → Reset Local
/// Cache"), none of which exists here. Every case has the same way out: both
/// local stores are copies of iCloud (the class in the shared store, her
/// membership row in the private one), so rebuilding them brings everything
/// back except marks this iPhone hasn't sent yet.
struct AssistantStartupProblem: Equatable {
    let message: String
    /// False when a store is still open (a rebuild after the iCloud account
    /// arrived that couldn't close the old one): deleting files under it
    /// would do harm, and reopening the app is the fix.
    let canRebuild: Bool

    /// `storesOpen`: whether a stack still holds the store files
    /// (`AssistantStack.isOpen`).
    init(_ error: Error, storesOpen: Bool = false) {
        canRebuild = !storesOpen
        guard canRebuild else {
            message = "Daybook Assistant needs to restart. Quit it and open it again."
            return
        }
        switch error {
        case CoreDataStackError.storeFromNewerBuild:
            // A TestFlight tester can install an earlier build over a later
            // one; the later build's data would be destroyed by opening it.
            message = "This copy of Daybook Assistant is older than the one that last opened "
                + "your class on this iPhone. Install the latest version from TestFlight, "
                + "or rebuild your class from iCloud."
        case CoreDataStackError.storeSchemaIncoherent:
            message = "Your class's copy on this iPhone is damaged. Rebuild it from iCloud to carry on."
        default:
            message = "Daybook Assistant couldn't open your class on this iPhone. "
                + "Quit and reopen the app, or rebuild your class from iCloud."
        }
    }
}
