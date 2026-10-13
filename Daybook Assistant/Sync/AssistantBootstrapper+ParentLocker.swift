import Foundation
import CoreData

// MARK: - ParentLocker

extension AssistantBootstrapper {

    /// Starts the class's ParentLocker sync on a newly built stack, in place
    /// of the last one's (a rebuild has new stores). Its send record goes
    /// into the classroom share like a mark (`AssistantSave`), so the guide
    /// and the other assistants see who sent it. It runs whichever method the
    /// guide picked: with email picked it only reads the settings and sends
    /// nothing. Never on the Sample Class, whose stack doesn't come through
    /// here.
    func startParentLocker(on stack: CoreDataStack) {
        parentLocker?.stop()
        let container = stack.container
        let sync = ParentLockerSync(context: stack.viewContext) { context, created in
            AssistantSave.save(context, container: container, created: created)
        }
        sync.start(watching: stack.viewContext)
        parentLocker = sync
    }

    /// The sync for the screens: none while the Sample Class is open, which
    /// goes nowhere.
    var parentLockerForScreens: ParentLockerSync? {
        AssistantSampleClass.isActive ? nil : parentLocker
    }
}
