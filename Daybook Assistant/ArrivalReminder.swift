import Foundation
import SwiftUI
import CoreData
import UserNotifications
import OSLog

/// "Arrival closes": a notification on school mornings at the time she sets
/// (8:15 unless changed), reminding her to close arrival so anyone not here
/// is marked absent. It never marks anyone itself.
///
/// Local notifications can't check the roll when they fire, so this keeps
/// one request per school day for the next `daysAhead` days and rebuilds them
/// whenever something could change the answer: launch, coming back to the
/// app, the setting, the guide's calendar arriving, and today's roll filling
/// up (once nobody is unmarked, today's request is withdrawn). Weekends and
/// the guide's days off come from the same `SchoolDayChecker` rule as the
/// grid's arrows.
@MainActor
enum ArrivalReminder {

    static let enabledKey = "Assistant.arrivalReminder.enabled"
    /// Minutes after midnight.
    static let timeKey = "Assistant.arrivalReminder.minutes"
    static let defaultMinutes = 8 * 60 + 15
    static let daysAhead = 10
    private static let idPrefix = "arrival-"

    private static let logger = Logger.app(category: "reminder")

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func minutes(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: timeKey) as? Int ?? defaultMinutes
    }

    /// When the next reminders fire: the set time on each of the next `count`
    /// school days, leaving out a time already past and, when `todayIsDone`,
    /// today. Pure, for the tests.
    static func fireDates(
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

    /// What the attendance screen calls as its roll changes: asks for
    /// notifications the first time a class is on screen, then rebuilds the
    /// reminders. The sample class schedules nothing.
    static func update(hasClass: Bool, in context: NSManagedObjectContext) async {
        if AssistantSampleClass.isActive { return }
        guard hasClass else { return }
        await requestPermissionIfNeeded()
        await reschedule(in: context)
    }

    /// Asks for permission once, the first time a class is on screen with the
    /// reminder on.
    static func requestPermissionIfNeeded() async {
        guard isEnabled() else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Removes every pending arrival reminder: before rescheduling, and when
    /// she leaves the classroom (they would otherwise go on firing for up to
    /// `daysAhead` school days, and a tap on one opened onboarding).
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// Replaces this app's pending reminders with the ones that should be
    /// there now.
    static func reschedule(in context: NSManagedObjectContext, now: Date = Date()) async {
        await cancelAll()
        let center = UNUserNotificationCenter.current()

        guard isEnabled() else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let calendar = AppCalendar.shared
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: daysAhead * 3, to: start) else { return }
        let nonSchoolDays = SchoolDayChecker.nonSchoolDaySet(in: start..<end, using: context, calendar: calendar)
        let dates = fireDates(
            from: now,
            minutes: minutes(),
            nonSchoolDays: nonSchoolDays,
            todayIsDone: isRollComplete(on: start, in: context),
            calendar: calendar
        )
        for date in dates {
            let content = UNMutableNotificationContent()
            content.title = "Arrival closes"
            content.body = "Close arrival to mark anyone not here yet absent."
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = idPrefix + AppCalendar.dayID(date)
            // A newer reschedule has started (the roll changed): it decides
            // now, and adding after its removal would bring back a reminder
            // it meant to drop.
            guard !Task.isCancelled else { return }
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            } catch {
                let reason = error.localizedDescription
                logger.error("Scheduling \(id, privacy: .public) failed: \(reason, privacy: .public)")
            }
        }
    }

    /// Whether everyone on `day`'s roll has a mark.
    static func isRollComplete(on day: Date, in context: NSManagedObjectContext) -> Bool {
        let records = (try? CDAttendanceStore(context: context, role: .assistant).loadRecords(for: day)) ?? []
        let winners = records.deduplicatedPerStudentDay()
        let roll = AssistantDayRoll.students(
            on: day, recordStudentIDs: Set(winners.map(\.studentID)), in: context
        ).compactMap { $0.id?.uuidString }
        guard !roll.isEmpty else { return false }
        let marked = Set(winners.filter { $0.status != .unmarked }.map(\.studentID))
        return roll.allSatisfy(marked.contains)
    }
}

/// Shows a reminder that fires while the app is open, and turns a tap on one
/// into "show today" for the attendance screen.
final class ArrivalReminderTaps: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ArrivalReminderTaps()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .assistantShowToday, object: nil)
        }
    }
}

/// Keeps the arrival reminders in step with the roll: rebuilt on every full
/// load (a day change, a return to the app, an import that may bring the
/// guide's calendar) and whenever today's unmarked count moves, so today's
/// goes once everyone's marked.
///
/// A modifier of its own, like `AssistantReloadOnReturn`: read in the
/// attendance screen's body, `loadGeneration` would redraw the whole grid on
/// every reload, which `Row`'s Equatable exists to avoid.
struct ArrivalReminderFollower: ViewModifier {
    let viewModel: AssistantAttendanceViewModel?
    let context: NSManagedObjectContext

    private var signature: String {
        guard let viewModel else { return "" }
        return "\(viewModel.loadGeneration)|\(viewModel.isToday ? viewModel.unmarkedCount : -1)"
    }

    func body(content: Content) -> some View {
        content.task(id: signature) {
            await ArrivalReminder.update(hasClass: viewModel?.rows.isEmpty == false, in: context)
        }
    }
}
