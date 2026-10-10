import CoreData

/// Keeps the reminders up to date without the attendance screen. The
/// screen's own follower (`ArrivalReminderFollower`) runs only while it is
/// on screen, so a pickup the guide set, moved or removed, a child marked
/// Left Early, or Back in Class, on another device while this iPhone was
/// locked left a stale reminder ringing, or a new pickup silent, until the
/// app was opened. The arrival and front-desk reminders were the same: a
/// roll finished or an email sent on another device still rang here.
///
/// `changed` comes on every import from iCloud (the remote-change stream
/// `AssistantBootstrapper` already follows, which a CloudKit push that wakes
/// the suspended app feeds too), from `AssistantApp` on every scene-phase
/// change, and from the attendance screen's follower on every load or mark
/// that could move a reminder. A burst settles until `delay` has passed since
/// its last change, then one `refresh` brings all three up to date. The wait
/// holds one background task assertion (`SiriSyncKeepAlive`), however many
/// changes it takes in, so leaving the app or a push wake still finishes it;
/// each change used to begin one of its own.
@MainActor
final class EarlyPickupReminderUpkeep {

    static let shared = EarlyPickupReminderUpkeep()
    static let delay: Duration = .seconds(1)

    /// Runs a wait under a background task assertion: `SiriSyncKeepAlive` in
    /// the app, a counter in the tests.
    typealias KeepAlive = @MainActor (_ name: String, _ work: @escaping @MainActor () async -> Void) -> Void

    private let delay: Duration
    private let keepAlive: KeepAlive
    private let rebuild: @MainActor (NSManagedObjectContext) async -> Void

    /// Counts calls to `changed`: the wait goes on until a whole `delay` has
    /// passed with none.
    private var generation = 0
    private var lastChange = ContinuousClock.now
    /// The latest change's way to the context, read when the wait ends.
    private var context: (@MainActor () -> NSManagedObjectContext?)?
    /// A wait is running under its background task; changes meanwhile join it.
    private(set) var isWaiting = false

    init(
        delay: Duration = EarlyPickupReminderUpkeep.delay,
        keepAlive: @escaping KeepAlive = { SiriSyncKeepAlive.run(named: $0, $1) },
        rebuild: @escaping @MainActor (NSManagedObjectContext) async -> Void = {
            await EarlyPickupReminderUpkeep.refresh(in: $0)
        }
    ) {
        self.delay = delay
        self.keepAlive = keepAlive
        self.rebuild = rebuild
    }

    /// Something may have changed a reminder. `context` is read when the wait
    /// ends: the classroom's (or the sample's) context then, or nil when
    /// there is no class to follow.
    func changed(context: @escaping @MainActor () -> NSManagedObjectContext?) {
        generation &+= 1
        lastChange = .now
        self.context = context
        guard !isWaiting else { return }
        isWaiting = true
        keepAlive("Update reminders") { [weak self] in
            await self?.settle()
        }
    }

    /// Waits until `delay` has passed since the last change, then rebuilds
    /// once. A change during the rebuild starts a wait of its own.
    private func settle() async {
        var seen: Int
        repeat {
            seen = generation
            try? await Task.sleep(until: lastChange + delay, clock: .continuous)
        } while seen != generation
        isWaiting = false
        let latest = context
        context = nil
        guard let context = latest?() else { return }
        await rebuild(context)
    }

    /// What a settled change runs: the pickups and, for a real class, the
    /// arrival and front-desk reminders, which an import changes just as
    /// often (the guide's days off and email settings, a send or the last
    /// marks from another device). None asks for permission: the alert
    /// belongs on screen.
    static func refresh(
        in context: NSManagedObjectContext,
        isSample: Bool = AssistantSampleClass.isActive,
        center: any ReminderCenter = SystemReminderCenter()
    ) async {
        await EarlyPickupReminder.reschedule(in: context, asksPermission: false, center: center)
        // As on screen: nothing for a class whose children haven't arrived
        // from iCloud yet.
        let children = AssistantDayRoll.classroomStudents(in: context)
        guard !isSample, ((try? context.count(for: children)) ?? 0) > 0 else { return }
        await ArrivalReminder.reschedule(in: context, center: center)
        await FrontDeskEmailReminder.reschedule(in: context, center: center)
    }
}

extension AssistantBootstrapper {
    /// Something may have changed a reminder: an import, the app coming or
    /// going, or the attendance screen's load or mark (`ArrivalReminderFollower`).
    /// The reminders follow the class in use (the sample's, when it's open),
    /// once there is one.
    func pickupRemindersMayHaveChanged() {
        EarlyPickupReminderUpkeep.shared.changed { [weak self] in
            guard let self, case .ready = phase else { return nil }
            return coreDataStack?.viewContext
        }
    }
}
