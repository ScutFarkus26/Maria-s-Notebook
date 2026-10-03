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
/// rebuilds them whenever the answer could change: every load of the grid (a
/// day change, coming back to the app, an import that brings someone else's
/// pickup), her own pickup edits and marks, and the setting. A child marked
/// absent or Left Early, or whose time is removed, loses theirs.
///
/// The sample class rings too, the one reminder it does, so Leaving Early…
/// can be tried there. Its requests carry their own prefix: leaving the
/// sample, or a relaunch that doesn't reopen it, takes them off.
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

    /// When a pickup's reminder fires: `lead` minutes before it, or nil
    /// once that has passed. Pure, for the tests.
    nonisolated static func fireDate(for leavesAt: Date, leadMinutes: Int, now: Date) -> Date? {
        let fire = leavesAt.addingTimeInterval(-Double(leadMinutes) * 60)
        return fire > now ? fire : nil
    }

    /// The pickups from `now` to `daysAhead` days on, one per child and day
    /// (the dedup winner's), leaving out children absent or already gone
    /// home and anyone not on the classroom roll.
    static func pendingPickups(in context: NSManagedObjectContext, now: Date = Date()) -> [Pickup] {
        let calendar = AppCalendar.shared
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: daysAhead, to: start) else { return [] }
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@", start as NSDate, end as NSDate
        )
        let records = context.safeFetch(request).deduplicatedPerStudentDay()
        let students = context.safeFetch(AssistantDayRoll.classroomStudents(in: context))
        let names = Dictionary(
            students.compactMap { student in student.id.map { ($0.uuidString, student.shortName) } },
            uniquingKeysWith: { first, _ in first }
        )
        return records.compactMap { record in
            guard let leavesAt = record.leavesAt, leavesAt > now,
                  record.status != .absent, record.status != .leftEarly,
                  let name = names[record.studentID] else { return nil }
            return Pickup(studentID: record.studentID, name: name, leavesAt: leavesAt, note: record.note ?? "")
        }
        .sorted { $0.leavesAt < $1.leavesAt }
    }

    /// Asks for permission once, the first time a pickup is set with the
    /// reminder on.
    static func requestPermissionIfNeeded() async {
        guard isEnabled() else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// A pickup's request identifier, one per child and day; the sample
    /// class's under their own prefix. Pure, for the tests.
    nonisolated static func requestID(studentID: String, leavesAt: Date, isSample: Bool) -> String {
        (isSample ? sampleIDPrefix : idPrefix) + studentID + "-" + AppCalendar.dayID(leavesAt)
    }

    /// Removes every pending pickup reminder, the sample class's included:
    /// before rescheduling, and when she leaves the classroom.
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

    /// Replaces this app's pending pickup reminders with the ones that should
    /// be there now.
    static func reschedule(in context: NSManagedObjectContext, now: Date = Date()) async {
        // Read once: leaving the sample mid-loop mustn't file its children
        // under the real class's prefix.
        let isSample = AssistantSampleClass.isActive
        await cancelAll()
        guard isEnabled() else { return }
        let pickups = pendingPickups(in: context, now: now)
        guard !pickups.isEmpty else { return }
        await requestPermissionIfNeeded()
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let lead = leadMinutes()
        let calendar = AppCalendar.shared
        for pickup in pickups {
            guard let fire = fireDate(for: pickup.leavesAt, leadMinutes: lead, now: now) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(pickup.name) leaves at \(AttendanceClock.string(pickup.leavesAt))"
            content.body = pickup.note.isEmpty
                ? "Early pickup. Mark Left Early when they go."
                : "\(pickup.note). Mark Left Early when they go."
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = requestID(studentID: pickup.studentID, leavesAt: pickup.leavesAt, isSample: isSample)
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
