import Foundation
import CoreData
import UserNotifications
import OSLog

/// "Maya S leaves at 1:30": a notification a few minutes (10 unless changed)
/// before each pickup time set with Leaving Early…, on this iPhone or by the
/// guide or another assistant. A tap opens today's grid. It never marks
/// anyone itself: Left Early is marked when the child goes.
///
/// Local notifications can't look at the roll when they fire, so this keeps
/// one request per pickup still to come over the next `daysAhead` days and
/// brings them up to date whenever the answer could change: every load of
/// the grid, her own pickup edits and marks, the setting, and, with the
/// screen closed or the phone locked, every import from iCloud and every
/// trip to and from the background (`EarlyPickupReminderUpkeep`). A child
/// marked absent or Left Early, or whose time is removed, loses theirs.
///
/// Bringing them up to date only adds and removes what differs from what's
/// pending (`changes(wanted:pending:)`), so the many imports that change no
/// pickup leave the requests alone.
///
/// The sample class rings too, the one reminder it does, so Leaving Early…
/// can be tried there. Its requests carry their own prefix, and each class
/// only ever compares against its own: leaving the sample, or a relaunch
/// that doesn't reopen it, takes them off.
@MainActor
enum EarlyPickupReminder {

    static let enabledKey = "Assistant.pickupReminder.enabled"
    /// How many minutes before the pickup the reminder comes.
    static let leadKey = "Assistant.pickupReminder.leadMinutes"
    static let defaultLeadMinutes = 10
    /// The lead times the settings offer.
    static let leadChoices = [5, 10, 15, 20, 30]
    nonisolated static let daysAhead = 10
    nonisolated private static let idPrefix = "pickup-"
    nonisolated private static let sampleIDPrefix = "pickup-sample-"

    private static let logger = Logger.app(category: "reminder")

    /// The run bringing the requests up to date, which the next one waits
    /// for: two at once could each read the pending requests before the
    /// other changed them, and an older one could put back a reminder the
    /// newer one had just taken off.
    private static var lastRun: Task<Void, Never>?

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func leadMinutes(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: leadKey) as? Int ?? defaultLeadMinutes
    }

    /// One pickup still to come: who, when, and the day's note.
    struct Pickup: Equatable {
        let studentID: String
        let name: String
        let leavesAt: Date
        let note: String
    }

    /// One notification request, as wanted or as pending: what the
    /// comparison looks at.
    struct Reminder: Equatable {
        let id: String
        let title: String
        let body: String
        /// To the minute, as the calendar trigger holds it.
        let fireDate: Date
    }

    /// What it takes to go from the pending requests to the wanted ones.
    struct Changes: Equatable {
        var add: [Reminder] = []
        var remove: [String] = []
    }

    /// When a pickup's reminder fires: `lead` minutes before it, or nil
    /// once that has passed. Pure, for the tests.
    nonisolated static func fireDate(for leavesAt: Date, leadMinutes: Int, now: Date) -> Date? {
        let fire = leavesAt.addingTimeInterval(-Double(leadMinutes) * 60)
        return fire > now ? fire : nil
    }

    /// The pickups from `now` to `daysAhead` days on, one per child and day:
    /// the time `AttendanceDeduplication.plannedPickup` reads across the
    /// day's copies, and the dedup winner's mark, leaving out children
    /// absent or already gone home and anyone not on the classroom roll.
    static func pendingPickups(in context: NSManagedObjectContext, now: Date = Date()) -> [Pickup] {
        let calendar = AppCalendar.shared
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: daysAhead, to: start) else { return [] }
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@", start as NSDate, end as NSDate
        )
        let fetched = context.safeFetch(request)
        let copies = Dictionary(grouping: fetched) { AttendanceDeduplication.studentDayKey($0) ?? "" }
        let students = context.safeFetch(AssistantDayRoll.classroomStudents(in: context))
        let names = Dictionary(
            students.compactMap { student in student.id.map { ($0.uuidString, student.shortName) } },
            uniquingKeysWith: { first, _ in first }
        )
        return fetched.deduplicatedPerStudentDay().compactMap { record in
            let day = copies[AttendanceDeduplication.studentDayKey(record) ?? ""] ?? [record]
            guard let leavesAt = AttendanceDeduplication.plannedPickup(among: day), leavesAt > now,
                  record.status != .absent, record.status != .leftEarly,
                  let name = names[record.studentID] else { return nil }
            return Pickup(studentID: record.studentID, name: name, leavesAt: leavesAt, note: record.note ?? "")
        }
        .sorted { $0.leavesAt < $1.leavesAt }
    }

    /// Asks for permission once, the first time a pickup is set with the
    /// reminder on.
    static func requestPermissionIfNeeded(center: any ReminderCenter = SystemReminderCenter()) async {
        guard isEnabled() else { return }
        guard await center.authorizationStatus() == .notDetermined else { return }
        _ = await center.requestAuthorization()
    }

    /// A pickup's request identifier: the child, the day and the time, so a
    /// moved pickup is a different request. The sample class's under their
    /// own prefix. Pure, for the tests.
    nonisolated static func requestID(studentID: String, leavesAt: Date, isSample: Bool) -> String {
        let time = AppCalendar.shared.dateComponents([.hour, .minute], from: leavesAt)
        let minutes = (time.hour ?? 0) * 60 + (time.minute ?? 0)
        return (isSample ? sampleIDPrefix : idPrefix) + studentID + "-" + AppCalendar.dayID(leavesAt) + "-\(minutes)"
    }

    /// Whether a pending request is one the class in use keeps: the sample's
    /// own while it's open, else the real class's, never the other's.
    nonisolated static func isOwn(_ id: String, isSample: Bool) -> Bool {
        isSample ? id.hasPrefix(sampleIDPrefix) : id.hasPrefix(idPrefix) && !id.hasPrefix(sampleIDPrefix)
    }

    /// The guide's note as a sentence: a full stop added unless it already
    /// ends in one ("Grandma picking up!" stays as it is, not "!.").
    nonisolated static func sentence(_ note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".!?…".contains(last) else { return trimmed }
        return trimmed + "."
    }

    /// The requests `pickups` call for: one per pickup whose reminder is
    /// still ahead. Pure, for the tests.
    static func reminders(for pickups: [Pickup], leadMinutes: Int, now: Date, isSample: Bool) -> [Reminder] {
        pickups.compactMap { pickup in
            guard let fire = fireDate(for: pickup.leavesAt, leadMinutes: leadMinutes, now: now) else { return nil }
            return Reminder(
                id: requestID(studentID: pickup.studentID, leavesAt: pickup.leavesAt, isSample: isSample),
                title: "\(pickup.name) leaves at \(AttendanceClock.string(pickup.leavesAt))",
                body: pickup.note.isEmpty
                    ? "Early pickup. Mark Left Early when they go."
                    : "\(sentence(pickup.note)) Mark Left Early when they go.",
                fireDate: toTheMinute(fire)
            )
        }
    }

    /// The adds and removes that turn `pending` into `wanted`: a request
    /// pending and wanted unchanged is left alone, one no longer wanted is
    /// removed, and one new or changed (its words or its time) is added,
    /// which replaces a pending one with the same identifier. Pure, for the
    /// tests.
    static func changes(wanted: [Reminder], pending: [Reminder]) -> Changes {
        let pendingByID = Dictionary(pending.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wantedIDs = Set(wanted.map(\.id))
        return Changes(
            add: wanted.filter { pendingByID[$0.id] != $0 },
            remove: pending.map(\.id).filter { !wantedIDs.contains($0) }
        )
    }

    /// Removes every pending pickup reminder, the sample class's included:
    /// when she leaves the classroom.
    static func cancelAll() async {
        await cancel(prefix: idPrefix)
    }

    /// Removes the sample class's pickup reminders only: when she leaves the
    /// sample, and at a launch that doesn't reopen it.
    static func cancelSample() async {
        await cancel(prefix: sampleIDPrefix)
    }

    private static func cancel(prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// Brings this app's pending pickup reminders up to date with the ones
    /// that should be there now, after any run already going. Asks for
    /// permission the first time there is a pickup, unless `asksPermission`
    /// is false (the background upkeep: the alert belongs on screen).
    static func reschedule(
        in context: NSManagedObjectContext,
        now: Date = Date(),
        asksPermission: Bool = true,
        center: any ReminderCenter = SystemReminderCenter()
    ) async {
        let previous = lastRun
        let run = Task {
            await previous?.value
            await bringUpToDate(in: context, now: now, asksPermission: asksPermission, center: center)
        }
        lastRun = run
        await run.value
    }

    private static func bringUpToDate(
        in context: NSManagedObjectContext,
        now: Date,
        asksPermission: Bool,
        center: any ReminderCenter
    ) async {
        // Read once: leaving the sample mid-run mustn't file its children
        // under the real class's prefix.
        let isSample = AssistantSampleClass.isActive
        var wanted: [Reminder] = []
        let pickups = isEnabled() ? pendingPickups(in: context, now: now) : []
        if !pickups.isEmpty {
            if asksPermission { await requestPermissionIfNeeded(center: center) }
            let status = await center.authorizationStatus()
            if status == .authorized || status == .provisional {
                wanted = reminders(for: pickups, leadMinutes: leadMinutes(), now: now, isSample: isSample)
            }
        }
        let pending = await center.pendingRequests().compactMap { request in
            pendingReminder(request, isSample: isSample)
        }
        let diff = changes(wanted: wanted, pending: pending)
        if !diff.remove.isEmpty {
            center.removePendingRequests(withIdentifiers: diff.remove)
        }
        let calendar = AppCalendar.shared
        for reminder in diff.add {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            } catch {
                let reason = error.localizedDescription
                logger.error("Scheduling \(reminder.id, privacy: .public) failed: \(reason, privacy: .public)")
            }
        }
    }

    /// A pending request as the comparison reads it, or nil when it isn't
    /// the class in use's pickup reminder.
    private static func pendingReminder(_ request: UNNotificationRequest, isSample: Bool) -> Reminder? {
        guard isOwn(request.identifier, isSample: isSample) else { return nil }
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        return Reminder(
            id: request.identifier,
            title: request.content.title,
            body: request.content.body,
            fireDate: trigger.flatMap { AppCalendar.shared.date(from: $0.dateComponents) } ?? .distantPast
        )
    }

    /// `date` with its seconds dropped, as a calendar trigger keeps it.
    private static func toTheMinute(_ date: Date) -> Date {
        let calendar = AppCalendar.shared
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }
}
