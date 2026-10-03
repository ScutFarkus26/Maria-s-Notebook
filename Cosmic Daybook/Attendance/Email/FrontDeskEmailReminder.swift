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
/// taking an import, a send recorded here, the setting. Once today's email has
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
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        return status == .authorized || status == .provisional
    }

    /// Removes every pending front-desk reminder.
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter(isReminder)
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// Replaces this device's pending reminders with the ones that should be
    /// there now. Nothing is scheduled while the guide's email isn't set up
    /// (no settings in the share, turned off, or no one to send to).
    static func reschedule(in context: NSManagedObjectContext, now: Date = Date()) async {
        await cancelAll()
        guard isEnabled(), let settings = AttendanceEmailLog.settings(in: context), settings.canSend else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let calendar = AppCalendar.shared
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: daysAhead * 3, to: start) else { return }
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
        for kind in kinds {
            let dates = fireDates(
                from: now, minutes: kind.minutes, nonSchoolDays: nonSchoolDays,
                todayIsDone: sentToday, calendar: calendar
            )
            for date in dates {
                let content = UNMutableNotificationContent()
                content.title = kind.title
                content.body = kind.body
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let id = idPrefix + AppCalendar.dayID(date) + "-" + kind.suffix
                // A newer reschedule has started: it decides now, and adding
                // after its removal would bring back a reminder it meant to drop.
                guard !Task.isCancelled else { return }
                do {
                    try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                } catch {
                    let reason = error.localizedDescription
                    logger.error("Scheduling \(id, privacy: .public) failed: \(reason, privacy: .public)")
                }
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

extension Notification.Name {
    /// A front-desk reminder was tapped: the attendance screen shows today and
    /// opens the email.
    static let frontDeskEmailRequested = Notification.Name("FrontDeskEmail.requested")
}
