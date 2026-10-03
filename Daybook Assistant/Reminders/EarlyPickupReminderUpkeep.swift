import CoreData

/// Keeps the early-pickup reminders up to date without the attendance
/// screen. The screen's own follower (`ArrivalReminderFollower`) runs only
/// while it is on screen, so a pickup the guide set, moved or removed, a
/// child marked Left Early, or Back in Class, on another device while this
/// iPhone was locked left a stale reminder ringing, or a new pickup silent,
/// until the app was opened.
///
/// `changed` comes on every import from iCloud (the remote-change stream
/// `AssistantBootstrapper` already follows, which a CloudKit push that wakes
/// the suspended app feeds too) and, from `AssistantApp`, on every
/// scene-phase change. A burst settles for `delay`, then one
/// `EarlyPickupReminder.reschedule` compares and changes only what differs. Each wait holds a background
/// task assertion (`SiriSyncKeepAlive`), so leaving the app or a push wake
/// still finishes it.
@MainActor
final class EarlyPickupReminderUpkeep {

    static let shared = EarlyPickupReminderUpkeep()
    static let delay: Duration = .seconds(1)

    /// Counts calls to `changed`: only the latest wait goes on to reschedule.
    private var generation = 0

    /// Something may have changed a pickup. `context` is read when the wait
    /// ends: the classroom's (or the sample's) context then, or nil when
    /// there is no class to follow.
    func changed(context: @escaping @MainActor () -> NSManagedObjectContext?) {
        generation &+= 1
        let mine = generation
        SiriSyncKeepAlive.run(named: "Update pickup reminders") { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard let self, mine == generation, let context = context() else { return }
            await EarlyPickupReminder.reschedule(in: context, asksPermission: false)
        }
    }
}

extension AssistantBootstrapper {
    /// Something may have changed a pickup while the attendance screen
    /// isn't running: an import, or the app coming or going. The reminders
    /// follow the class in use (the sample's, when it's open), once there
    /// is one.
    func pickupRemindersMayHaveChanged() {
        EarlyPickupReminderUpkeep.shared.changed { [weak self] in
            guard let self, case .ready = phase else { return nil }
            return coreDataStack?.viewContext
        }
    }
}
