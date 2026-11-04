import Foundation
import CoreData
import OSLog

// MARK: - ParentLocker

extension AssistantBootstrapper {
    private static let parentLockerLogger = Logger.app(category: "bootstrap")

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

    /// How long a rebuild waits for a ParentLocker send under way.
    nonisolated static let parentLockerRebuildWait: Duration = .seconds(10)

    /// Before a rebuild takes the stores off: a ParentLocker send under way
    /// finishes on the old stack first, up to `limit`, as a running attach
    /// does (`waitForAttachBeforeRebuild`). Cut off, its save reached
    /// ParentLocker but its send record failed on the dead context, the new
    /// stack's sync found nothing recorded, and every phone's "attendance is
    /// late" reminders rang (bug hunt 2026-11-03 #1). Then the sync stops, so
    /// nothing new starts on stores about to go; a send still going at the
    /// limit writes nothing when it ends (`ParentLockerSync.stop`). Call it
    /// once the rebuild is sure to happen: the stopped sync is replaced only
    /// by the rebuilt stack's (`startParentLocker`).
    func finishParentLockerBeforeRebuild(upTo limit: Duration = parentLockerRebuildWait) async {
        guard let parentLocker else { return }
        if !(await parentLocker.waitForRun(upTo: limit)) {
            Self.parentLockerLogger.notice("A ParentLocker send is still going; rebuilding anyway, it records nothing")
        }
        parentLocker.stop()
    }

    /// The sync for the screens: none while the Sample Class is open, which
    /// goes nowhere.
    var parentLockerForScreens: ParentLockerSync? {
        AssistantSampleClass.isActive ? nil : parentLocker
    }
}
