import Foundation
import CoreData
import UserNotifications
import OSLog

/// "Front desk email": on school days when nobody has sent the day's
/// attendance email yet, a notification a few minutes before the guide's
/// deadline (10 before 9:00 unless changed) and a firmer one at the deadline.
/// A tap opens the attendance screen with the email ready. It never sends
/// anything itself.
///
/// Compiled into both apps. The deadline is the guide's, from the classroom
/// share (`AttendanceEmailLog.Settings.deadlineMinutes`); the switch and the
/// lead time are this device's own (whoever wants the nudge turns it on): on
/// by default in the Daybook Assistant, whose people take the roll, off in
/// the notebook.
///
/// Local notifications can't look at the store when they fire, so this keeps
/// one request per school day for the next `daysAhead` days and rebuilds them
/// whenever the answer could change: launch, the attendance screen loading or
/// taking an import, a send recorded here, the setting, and in the Assistant
/// every import with the screen closed (`EarlyPickupReminderUpkeep`). Once today's email has
/// gone, today's request is withdrawn. A device that hasn't heard yet that
/// someone else sent it can still ring; its tap then shows who did.
@MainActor
enum FrontDeskEmailReminder {

    static let enabledKey = "FrontDeskEmailReminder.enabled"
    /// How many minutes before the deadline the first reminder comes.
    static let leadKey = "FrontDeskEmailReminder.leadMinutes"
    static let defaultLeadMinutes = 10
    /// The lead times the settings offer.
    static let leadChoices = [5, 10, 15, 20, 30]
    nonisolated static let daysAhead = 10
    nonisolated private static let idPrefix = "frontdesk-"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CosmicDaybook", category: "FrontDeskEmailReminder"
    )

    #if ASSISTANT_APP
    static let isOnByDefault = true
    #else
    static let isOnByDefault = false
    #endif

    /// Set by a tapped reminder and cleared by the attendance screen once it
    /// has opened the email. A flag rather than only a notification, because
    /// a tap that launches the app arrives before any screen is listening.
    static var isEmailRequested = false

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? isOnByDefault
    }

    static func leadMinutes(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: leadKey) as? Int ?? defaultLeadMinutes
    }

    /// Whether a delivered notification is one of these.
    nonisolated static func isReminder(_ identifier: String) -> Bool {
        identifier.hasPrefix(idPrefix)
    }

    /// What a tapped reminder does in either app: remember the request and
    /// tell an open attendance screen.
    static func handleTap() {
        isEmailRequested = true
        NotificationCenter.default.post(name: .frontDeskEmailRequested, object: nil)
    }

    /// When the next reminders fire: the set time on each of the next `count`
    /// school days, leaving out a time already past and, when `todayIsDone`,
    /// today. Pure, for the tests; the Assistant's arrival reminder uses it too.
    nonisolated static func fireDates(
        from now: Date,
        minutes: Int,
        nonSchoolDays: Set<Date>,
        count: Int = daysAhead,
        todayIsDone: Bool,
        calendar: Calendar = AppCalendar.shared
    ) -> [Date] {
        var dates: [Date] = []
        var day = calendar.startOfDay(for: now)
        let today = day
        for _ in 0..<(count * 3) where dates.count < count {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
            guard !nonSchoolDays.contains(day) else { continue }
            if day == today, todayIsDone { continue }
            guard let fire = calendar.date(byAdding: .minute, value: minutes, to: day), fire > now else { continue }
            dates.append(fire)
        }
        return dates
    }

    /// Asks for permission, when the switch is turned on. Returns whether
    /// notifications may show.
    static func requestPermission(center: any ReminderCenter = SystemReminderCenter()) async -> Bool {
        let status = await center.authorizationStatus()
        if status == .notDetermined {
            return await center.requestAuthorization()
        }
        return status == .authorized || status == .provisional
    }

    /// One rebuild at a time (`ReminderRuns`).
    private static let runs = ReminderRuns()

    /// Removes every pending front-desk reminder, after any rebuild already
    /// going.
    static func cancelAll(center: any ReminderCenter = SystemReminderCenter()) async {
        await runs.run {
            await ReminderRuns.replace(where: isReminder, with: [], center: center, logger: logger)
        }
    }

    /// Replaces this device's pending reminders with the ones that should be
    /// there now. Nothing is scheduled while the guide's email isn't set up
    /// (no settings in the share, turned off, or no one to send to).
    static func reschedule(
        in context: NSManagedObjectContext,
        now: Date = Date(),
        center: any ReminderCenter = SystemReminderCenter()
    ) async {
        await runs.run(for: context) {
            let requests = await wantedRequests(in: context, now: now, center: center)
            await ReminderRuns.replace(where: isReminder, with: requests, center: center, logger: logger)
        }
    }

    /// The requests that should be pending now: none while the email isn't
    /// set up, the switch is off, or notifications aren't allowed.
    private static func wantedRequests(
        in context: NSManagedObjectContext,
        now: Date,
        center: any ReminderCenter
    ) async -> [UNNotificationRequest] {
        guard isEnabled(), let settings = AttendanceEmailLog.settings(in: context), settings.canSend else { return [] }
        let status = await center.authorizationStatus()
        guard status == .authorized || status == .provisional else { return [] }

        let calendar = AppCalendar.shared
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: daysAhead * 3, to: start) else { return [] }
        let nonSchoolDays = SchoolDayChecker.nonSchoolDaySet(in: start..<end, using: context, calendar: calendar)
        let sentToday = AttendanceEmailLog.latestSend(on: start, in: context) != nil
        let deadline = settings.deadlineMinutes
        let dueAt = timeString(deadline)
        let kinds = [
            Kind(suffix: "soon", minutes: deadline - leadMinutes(), title: "Front desk email due at \(dueAt)",
                 body: "Today's attendance hasn't been emailed to the front desk yet."),
            Kind(suffix: "due", minutes: deadline, title: "Front desk email is late",
                 body: "It was due at \(dueAt). Close arrival and email the front desk.")
        ]
        return kinds.flatMap { kind in
            fireDates(
                from: now, minutes: kind.minutes, nonSchoolDays: nonSchoolDays,
                todayIsDone: sentToday, calendar: calendar
            ).map { date in
                let content = UNMutableNotificationContent()
                content.title = kind.title
                content.body = kind.body
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let id = idPrefix + AppCalendar.dayID(date) + "-" + kind.suffix
                return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            }
        }
    }

    /// One of the day's two reminders: before the deadline, and at it.
    private struct Kind {
        let suffix: String
        let minutes: Int
        let title: String
        let body: String
    }

    /// "9:00 AM" for minutes after midnight.
    static func timeString(_ minutes: Int, calendar: Calendar = .current) -> String {
        let midnight = calendar.startOfDay(for: Date())
        let time = calendar.date(byAdding: .minute, value: minutes, to: midnight) ?? midnight
        return time.formatted(date: .omitted, time: .shortened)
    }
}

/// The parts of the notification center the reminders use: the system's
/// (`SystemReminderCenter`), or a stand-in in the tests, where the
/// simulator's own center has no permission to schedule anything.
@MainActor
protocol ReminderCenter {
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Asks for alerts and sounds; returns whether they were allowed.
    func requestAuthorization() async -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    func removePendingRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
}

/// The system's notification center.
struct SystemReminderCenter: ReminderCenter {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
}

/// Rebuilds of one kind of reminder, one at a time and each to the end.
///
/// The attendance screen starts a rebuild from a task that SwiftUI cancels on
/// a tab switch or a newer change. A rebuild that stopped there, after
/// removing the old reminders and before adding the new ones, left none:
/// no reminder the next morning. So a rebuild runs in a task of its own that
/// a cancelled caller doesn't stop, after any rebuild already going, so an
/// older one can never put back what a newer one removed.
///
/// A rebuild still waiting for its turn when a newer one of the same context
/// is asked for is skipped, and its caller waits for the newer one instead:
/// that one reads the store later and makes the requests exactly what they
/// should be, whatever was pending. Marking 22 children used to queue about
/// 22 rebuilds and run every one.
@MainActor
final class ReminderRuns {
    private var last: Task<Bool, Never>?
    /// Numbers each rebuild asked for.
    private var asked = 0
    /// The newest rebuild asked for each context, by identity, and its task.
    private var newest: [ObjectIdentifier: (number: Int, task: Task<Bool, Never>)] = [:]

    /// Runs `work` after the rebuild before it, and waits for it, or for the
    /// newer rebuild of `context` that took its place. One with no context
    /// (taking them all off) is never skipped and never takes another's place.
    func run(for context: NSManagedObjectContext? = nil, _ work: @escaping @MainActor () async -> Void) async {
        asked &+= 1
        let number = asked
        let key = context.map(ObjectIdentifier.init)
        let previous = last
        let task = Task { () -> Bool in
            _ = await previous?.value
            // A newer one of this context is queued behind: it does the work.
            if let key, newest[key]?.number != number { return false }
            await work()
            return true
        }
        last = task
        guard let key else {
            _ = await task.value
            return
        }
        newest[key] = (number, task)
        var waitedFor = number
        var ran = await task.value
        while !ran, let newer = newest[key], newer.number != waitedFor {
            waitedFor = newer.number
            ran = await newer.task.value
        }
        if newest[key]?.number == waitedFor { newest[key] = nil }
    }

    /// Makes the pending requests that `isOurs` picks out exactly `requests`,
    /// built beforehand: ones no longer wanted are removed, and ones new or
    /// changed are added, which replaces a pending one with the same
    /// identifier. One pending and wanted unchanged is left alone, as the
    /// pickup reminders do (`EarlyPickupReminder.changes`): a rebuild with
    /// nothing new used to add every one again, about 30 between the
    /// Assistant's arrival and front-desk reminders, on every import.
    static func replace(
        where isOurs: (String) -> Bool,
        with requests: [UNNotificationRequest],
        center: any ReminderCenter,
        logger: Logger
    ) async {
        let pending = await center.pendingRequests().filter { isOurs($0.identifier) }
        let wanted = Set(requests.map(\.identifier))
        let stale = pending.map(\.identifier).filter { !wanted.contains($0) }
        if !stale.isEmpty { center.removePendingRequests(withIdentifiers: stale) }
        let pendingByID = Dictionary(
            pending.compactMap { request in Reminder(request).map { (request.identifier, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        for request in requests {
            if let reminder = Reminder(request), pendingByID[request.identifier] == reminder { continue }
            do {
                try await center.add(request)
            } catch {
                let id = request.identifier
                let reason = error.localizedDescription
                logger.error("Scheduling \(id, privacy: .public) failed: \(reason, privacy: .public)")
            }
        }
    }

    /// One request as the comparison reads it, wanted or pending: its words
    /// and when it fires, as the calendar trigger holds it (to the minute).
    /// The builders vary nothing else; the sound is the default on every
    /// one. Nil for any other trigger, which is always added again.
    private struct Reminder: Equatable {
        let title: String
        let body: String
        let fireTime: [Int?]
        let repeats: Bool

        init?(_ request: UNNotificationRequest) {
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
            let time = trigger.dateComponents
            title = request.content.title
            body = request.content.body
            fireTime = [time.year, time.month, time.day, time.hour, time.minute]
            repeats = trigger.repeats
        }
    }
}

extension Notification.Name {
    /// A front-desk reminder was tapped: the attendance screen shows today and
    /// opens the email.
    static let frontDeskEmailRequested = Notification.Name("FrontDeskEmail.requested")
}
