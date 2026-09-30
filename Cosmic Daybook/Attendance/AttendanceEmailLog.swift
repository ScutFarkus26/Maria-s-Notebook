import Foundation
import CoreData

/// The front-desk attendance email's two shared records: the day's email went
/// (`CDAttendanceEmailSend`), and the guide's settings it is written from
/// (`CDAttendanceEmailSettings`).
///
/// Both live in the classroom share (schema 12), so the notebook and the
/// Daybook Assistant read the same ones: whoever finishes the roll can send
/// the email, everyone sees that it went and who sent it, and an assistant's
/// email goes to the guide's recipients in the guide's format. The only
/// reader and writer of both types; callers save (and, in the Assistant, put
/// a new send into the share, as for a mark).
enum AttendanceEmailLog {

    /// The front desk needs the day's attendance by 9:00 unless the guide says otherwise.
    nonisolated static let defaultDeadlineMinutes = 9 * 60
    /// How long before the deadline the screens start counting down to it.
    nonisolated static let dueWindowMinutes = 30

    /// Where today stands against the deadline, before anyone has sent it.
    enum Urgency: Equatable {
        /// Not today, or not yet close.
        case none
        /// Within `dueWindowMinutes` of the deadline.
        case due(Date)
        /// The deadline has passed.
        case overdue(Date)
    }

    /// Only today counts down: another day's email is either sent or not.
    static func urgency(
        for day: Date, deadlineMinutes: Int, now: Date = Date(), calendar: Calendar = .current
    ) -> Urgency {
        guard calendar.isDate(day, inSameDayAs: now),
              let deadline = calendar.date(byAdding: .minute, value: deadlineMinutes, to: calendar.startOfDay(for: day))
        else { return .none }
        if now >= deadline { return .overdue(deadline) }
        let dueFrom = deadline.addingTimeInterval(-Double(dueWindowMinutes) * 60)
        return now >= dueFrom ? .due(deadline) : .none
    }

    /// What an email is written from.
    struct Settings: Equatable, Sendable {
        var isEnabled: Bool
        /// The recipients as typed: commas or semicolons between.
        var toAddresses: String
        var nameOrder: AttendanceEmailNameOrder
        var groupByLevel: Bool
        /// When the front desk needs it by, in minutes after midnight.
        var deadlineMinutes: Int = AttendanceEmailLog.defaultDeadlineMinutes

        var recipients: [String] { AttendanceEmail.parseRecipients(from: toAddresses) }

        /// Turned on, with someone to send to.
        var canSend: Bool { isEnabled && !recipients.isEmpty }

        /// The day's email, ready for Mail.
        func draft(
            for day: Date,
            present: [AttendanceEmailStudent],
            tardy: [AttendanceEmailStudent],
            absent: [AttendanceEmailStudent]
        ) -> AttendanceEmailDraft {
            AttendanceEmailDraft(
                recipients: recipients,
                subject: AttendanceEmailReport.makeSubject(for: day),
                body: AttendanceEmailReport.makeBody(
                    present: present, tardy: tardy, absent: absent, date: day,
                    nameOrder: nameOrder, groupByLevel: groupByLevel
                )
            )
        }
    }

    /// One send, as the screens show it.
    struct Send: Equatable, Sendable {
        let sentAt: Date
        let sentBy: CDClassroomMembership.ClassroomRole?
        let sentByID: String?
        let sentByName: String?
        let wasConfirmedByHand: Bool

        init(_ record: CDAttendanceEmailSend) {
            sentAt = record.sentAt ?? .distantPast
            sentBy = record.sentBy.flatMap(CDClassroomMembership.ClassroomRole.init(rawValue:))
            sentByID = record.sentByID
            sentByName = record.sentByName
            wasConfirmedByHand = record.wasConfirmedByHand
        }

        /// Who sent it, as the viewer should read it: "you", an assistant's
        /// name, or the guide ("your guide" to an assistant).
        func senderName(
            viewerRole: CDClassroomMembership.ClassroomRole,
            myRecordName: String?,
            myName: String?,
            guideName: String? = nil
        ) -> String {
            if let id = sentByID, let mine = myRecordName, id == mine { return "you" }
            switch sentBy {
            case .leadGuide:
                return viewerRole == .leadGuide ? "you" : (guideName ?? "your guide")
            case .assistant:
                // Her own send from a phone that has no record name yet (or
                // the Sample Class, which has neither a name nor an id).
                if viewerRole == .assistant, sentByName == myName, sentByID == nil || sentByID == myRecordName {
                    return "you"
                }
                return sentByName ?? "an assistant"
            case nil:
                return "someone"
            }
        }

        /// "Sent 8:42 AM by Sarah", or "Marked sent …" when Mail couldn't
        /// confirm it, with "(late)" after the day's deadline. The date shows
        /// too when it went on another day than the one it reports.
        func summary(
            senderName: String, for day: Date, deadlineMinutes: Int? = nil, calendar: Calendar = .current
        ) -> String {
            let when = calendar.isDate(sentAt, inSameDayAs: day)
                ? sentAt.formatted(date: .omitted, time: .shortened)
                : sentAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            let verb = wasConfirmedByHand ? "Marked sent" : "Sent"
            let late = deadlineMinutes
                .flatMap { calendar.date(byAdding: .minute, value: $0, to: calendar.startOfDay(for: day)) }
                .map { sentAt > $0 } ?? false
            return "\(verb) \(when) by \(senderName)" + (late ? " (late)" : "")
        }
    }

    // MARK: - Sends

    /// The day's sends, newest first.
    static func sends(on day: Date, in context: NSManagedObjectContext) -> [CDAttendanceEmailSend] {
        let request = CDFetchRequest(CDAttendanceEmailSend.self)
        request.predicate = NSPredicate(format: "date == %@", AppCalendar.startOfDay(day) as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: false)]
        return context.safeFetch(request)
    }

    /// The newest send for `day`, if the email has gone.
    static func latestSend(on day: Date, in context: NSManagedObjectContext) -> Send? {
        let request = CDFetchRequest(CDAttendanceEmailSend.self)
        request.predicate = NSPredicate(format: "date == %@", AppCalendar.startOfDay(day) as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: false)]
        request.fetchLimit = 1
        return context.safeFetchFirst(request).map(Send.init)
    }

    /// Records that `day`'s email went, stamped with who this device is. The
    /// caller saves, and in the Assistant puts the new record into the share.
    @discardableResult
    static func recordSend(
        on day: Date,
        role: CDClassroomMembership.ClassroomRole,
        confirmedByHand: Bool = false,
        now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> CDAttendanceEmailSend {
        let send = CDAttendanceEmailSend(context: context)
        if let store = destinationStore(for: role, in: context) { context.assign(send, to: store) }
        send.date = AppCalendar.startOfDay(day)
        send.sentAt = now
        send.sentBy = role.rawValue
        send.sentByID = ClassroomIdentity.currentUserRecordName
        // Only assistants carry a name, as on their marks: the guide's sends
        // read as "you" on the guide's devices and "your guide" on theirs.
        send.sentByName = role == .assistant ? ClassroomIdentity.displayName : nil
        send.wasConfirmedByHand = confirmedByHand
        return send
    }

    /// The day's send as someone outside the classroom reads it ("Sent
    /// 8:42 AM by Sarah (late)", the guide's own "by the guide"), for MCP.
    static func thirdPersonSummary(on day: Date, in context: NSManagedObjectContext) -> String? {
        guard let send = latestSend(on: day, in: context) else { return nil }
        let name = send.sentBy == .leadGuide ? "the guide" : (send.sentByName ?? "an assistant")
        return send.summary(senderName: name, for: day, deadlineMinutes: settings(in: context)?.deadlineMinutes)
    }

    // MARK: - Settings

    /// The guide's settings as the share carries them, or nil before the guide
    /// has sent them (an older notebook, or before the first sync).
    static func settings(in context: NSManagedObjectContext) -> Settings? {
        newestSettingsRow(in: context).map { row in
            Settings(
                isEnabled: row.isEnabled,
                toAddresses: row.toAddresses ?? "",
                nameOrder: row.nameOrderRaw.flatMap(AttendanceEmailNameOrder.init(rawValue:)) ?? .firstLast,
                groupByLevel: row.groupByLevel,
                deadlineMinutes: Int(row.deadlineMinutes)
            )
        }
    }

    /// Writes the guide's settings into the share. Only the lead guide may,
    /// and nothing is written when they already match. Returns whether
    /// anything changed; the caller saves.
    @discardableResult
    static func saveSettings(
        _ settings: Settings,
        role: CDClassroomMembership.ClassroomRole,
        now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> Bool {
        guard role == .leadGuide else { return false }
        let request = CDFetchRequest(CDAttendanceEmailSettings.self)
        request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        let rows = context.safeFetch(request)
        if rows.count == 1, self.settings(in: context) == settings { return false }

        // Two of the guide's devices can each write one before either syncs:
        // keep the newest, drop the rest.
        rows.dropFirst().forEach(context.delete)
        let row: CDAttendanceEmailSettings
        if let newest = rows.first {
            row = newest
        } else {
            row = CDAttendanceEmailSettings(context: context)
            if let store = destinationStore(for: role, in: context) { context.assign(row, to: store) }
        }
        row.isEnabled = settings.isEnabled
        row.toAddresses = settings.toAddresses
        row.nameOrderRaw = settings.nameOrder.rawValue
        row.groupByLevel = settings.groupByLevel
        row.deadlineMinutes = Int32(settings.deadlineMinutes)
        row.modifiedAt = now
        return true
    }

    private static func newestSettingsRow(in context: NSManagedObjectContext) -> CDAttendanceEmailSettings? {
        let request = CDFetchRequest(CDAttendanceEmailSettings.self)
        request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        request.fetchLimit = 1
        return context.safeFetchFirst(request)
    }

    // MARK: - Stores

    /// Where a new record goes: the guide's own records live in the private
    /// store and join the share from there (`SharedStoreOrphanGuard`); an
    /// assistant's go straight into the shared store, as her marks do
    /// (`CDAttendanceStore`). Nil with a single store (tests, Sample Class).
    private static func destinationStore(
        for role: CDClassroomMembership.ClassroomRole,
        in context: NSManagedObjectContext
    ) -> NSPersistentStore? {
        guard let stores = context.persistentStoreCoordinator?.persistentStores, stores.count > 1 else { return nil }
        let wanted = role == .assistant ? CoreDataStack.sharedConfiguration : CoreDataStack.privateConfiguration
        return stores.first { $0.configurationName == wanted }
    }
}
