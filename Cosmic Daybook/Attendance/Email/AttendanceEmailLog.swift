import Foundation
import CoreData

/// How the day's attendance goes to the school (schema 18): the front-desk
/// email, or the school's ParentLocker site. The guide picks one in Settings;
/// it travels in the shared settings row, and each send records the one it
/// went by. Raw values are stored: never rename a case.
nonisolated enum AttendanceSendMethod: String, CaseIterable, Sendable {
    case email
    case parentLocker

    /// A stored value, or email for a row written before schema 18 (or a
    /// value this build doesn't know).
    init(stored raw: String?) {
        self = raw.flatMap(AttendanceSendMethod.init(rawValue:)) ?? .email
    }
}

/// The front-desk attendance email's two shared records: the day's email went
/// (`CDAttendanceEmailSend`), and the guide's settings it is written from
/// (`CDAttendanceEmailSettings`). Since schema 18 they also carry the
/// ParentLocker method: which way the guide picked, and which way each send
/// went.
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

    /// The two moments on `day` the screens' email line changes, where
    /// `urgency` turns due and then late: half an hour before the due time,
    /// and at it.
    static func changeTimes(on day: Date, deadlineMinutes: Int, calendar: Calendar = .current) -> [Date] {
        guard let deadline = calendar.date(
            byAdding: .minute, value: deadlineMinutes, to: calendar.startOfDay(for: day)
        ) else { return [] }
        return [deadline.addingTimeInterval(-Double(dueWindowMinutes) * 60), deadline]
    }

    /// The school's ParentLocker site until the guide sets another.
    nonisolated static let defaultParentLockerSite = "yyli.parentlocker.com"

    /// The host part of what the guide typed for the ParentLocker site:
    /// lowercased, without a scheme, path or spaces. Blank reads as the
    /// default, so a cleared field never leaves the app without a site.
    nonisolated static func parentLockerHost(_ typed: String?) -> String {
        var host = (typed ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where host.hasPrefix(scheme) {
            host.removeFirst(scheme.count)
        }
        host = String(host.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        return host.isEmpty ? defaultParentLockerSite : host
    }

    /// What the day's attendance is sent by, and what an email is written from.
    struct Settings: Equatable, Sendable {
        /// Whether the guide has the email turned on. With ParentLocker picked
        /// the shared row always holds false (`shared`), so an Assistant build
        /// from before schema 18, which knows only this, stops offering the
        /// email; the guide's own switch stays in the notebook's preferences.
        var isEnabled: Bool
        /// The recipients, ", " between (`AttendanceEmail.sharedAddressLine`);
        /// a row written before 2026-10-10 has them as typed.
        var toAddresses: String
        var nameOrder: AttendanceEmailNameOrder
        var groupByLevel: Bool
        /// When the front desk needs it by, in minutes after midnight.
        var deadlineMinutes: Int = AttendanceEmailLog.defaultDeadlineMinutes
        /// How the day's attendance goes to the school (schema 18).
        var sendMethod: AttendanceSendMethod = .email
        /// The ParentLocker host (schema 18), as `parentLockerHost` reads it.
        var parentLockerSite: String = AttendanceEmailLog.defaultParentLockerSite

        var recipients: [String] { AttendanceEmail.parseRecipients(from: toAddresses) }

        /// The email can go: email is the method, turned on, with someone to
        /// send to. The email's own buttons ask this.
        var canSend: Bool { sendMethod == .email && isEnabled && !recipients.isEmpty }

        /// The day's attendance has somewhere to go by the method picked:
        /// ParentLocker, or an email that `canSend`. What the reminder asks.
        /// Whether this device is signed in to ParentLocker is its own
        /// question: the reminder rings either way, since someone must send.
        var canSendAttendance: Bool { sendMethod == .parentLocker || canSend }

        /// The settings as the shared row holds them: with ParentLocker picked
        /// the email reads as off (see `isEnabled`), and the site as its host.
        var shared: Settings {
            var row = self
            if sendMethod == .parentLocker { row.isEnabled = false }
            row.parentLockerSite = AttendanceEmailLog.parentLockerHost(parentLockerSite)
            return row
        }

        /// The day's email, ready for Mail.
        func draft(
            for day: Date,
            present: [AttendanceEmailStudent],
            tardy: [AttendanceEmailStudent],
            absent: [AttendanceEmailStudent],
            leftEarly: [AttendanceEmailStudent] = []
        ) -> AttendanceEmailDraft {
            AttendanceEmailDraft(
                recipients: recipients,
                subject: AttendanceEmailReport.makeSubject(for: day),
                body: AttendanceEmailReport.makeBody(
                    present: present, tardy: tardy, absent: absent, leftEarly: leftEarly, date: day,
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
        /// Which way it went; a send recorded before schema 18 was an email.
        let channel: AttendanceSendMethod

        init(_ record: CDAttendanceEmailSend) {
            sentAt = record.sentAt ?? .distantPast
            sentBy = record.sentBy.flatMap(CDClassroomMembership.ClassroomRole.init(rawValue:))
            sentByID = record.sentByID
            sentByName = record.sentByName
            wasConfirmedByHand = record.wasConfirmedByHand
            channel = AttendanceSendMethod(stored: record.channelRaw)
        }

        /// Who sent it, as the viewer should read it: "you", an assistant's
        /// name, or the guide. Names come from the classroom's list first
        /// (`names`, by the sender's record name, so a rename reaches old
        /// sends), then from the send; to an assistant the guide is the name
        /// he set, then `guideName` (Apple's), then "your guide".
        func senderName(
            viewerRole: CDClassroomMembership.ClassroomRole,
            myRecordName: String?,
            myName: String?,
            guideName: String? = nil,
            names: ClassroomNames.Snapshot = ClassroomNames.Snapshot()
        ) -> String {
            // A stand-in such as `__defaultOwner__`, on either side, is no ID:
            // every device once saved the same one, so it matched the guide's sends.
            let sentByID = ClassroomIdentity.realRecordName(sentByID)
            let myRecordName = ClassroomIdentity.realRecordName(myRecordName)
            if let id = sentByID, let mine = myRecordName, id == mine { return "you" }
            let current = names.name(forRecordName: sentByID)
            switch sentBy {
            case .leadGuide:
                guard viewerRole == .assistant else { return "you" }
                return current ?? names.guideName ?? guideName ?? "your guide"
            case .assistant:
                // Her own send from a phone that has no record name yet (or
                // the Sample Class, which has neither a name nor an id).
                if viewerRole == .assistant, sentByName == myName, sentByID == nil || sentByID == myRecordName {
                    return "you"
                }
                return current ?? sentByName ?? "an assistant"
            case nil:
                return "someone"
            }
        }

        /// "Emailed 8:42 AM by Sarah" or "Sent to ParentLocker 8:47 AM by
        /// Sarah", or "Marked as sent …" when it couldn't be confirmed and the
        /// sender said it went, with "(late)" after the day's deadline. The
        /// date shows too when it went on another day than the one it reports.
        func summary(
            senderName: String, for day: Date, deadlineMinutes: Int? = nil, calendar: Calendar = .current
        ) -> String {
            let when = calendar.isDate(sentAt, inSameDayAs: day)
                ? sentAt.formatted(date: .omitted, time: .shortened)
                : sentAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            let verb = switch (channel, wasConfirmedByHand) {
            case (.email, false): "Emailed"
            case (.email, true): "Marked as sent"
            case (.parentLocker, false): "Sent to ParentLocker"
            case (.parentLocker, true): "Marked as sent to ParentLocker"
            }
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
        scopeToClassroom(request, in: context)
        return context.safeFetch(request)
    }

    /// The newest send for `day`, if the email has gone.
    static func latestSend(on day: Date, in context: NSManagedObjectContext) -> Send? {
        let request = CDFetchRequest(CDAttendanceEmailSend.self)
        request.predicate = NSPredicate(format: "date == %@", AppCalendar.startOfDay(day) as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: false)]
        request.fetchLimit = 1
        scopeToClassroom(request, in: context)
        return context.safeFetchFirst(request).map(Send.init)
    }

    /// Records that `day`'s attendance went, by `channel` (the email unless
    /// said), stamped with who this device is. The caller saves, and in the
    /// Assistant puts the new record into the share.
    @discardableResult
    static func recordSend(
        on day: Date,
        role: CDClassroomMembership.ClassroomRole,
        channel: AttendanceSendMethod = .email,
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
        // read as "you" on the guide's devices and, on theirs, as the name he
        // set in the classroom's list (`ClassroomNames`), else "your guide".
        send.sentByName = role == .assistant ? ClassroomIdentity.displayName : nil
        send.wasConfirmedByHand = confirmedByHand
        send.channelRaw = channel.rawValue
        return send
    }

    /// The day's send as someone outside the classroom reads it ("Emailed
    /// 8:42 AM by Sarah (late)", the guide's own "by the guide"), for MCP. An
    /// assistant is named as she goes by now (the classroom's list, by the
    /// send's record name, so a rename reaches old sends), then by the name
    /// stamped on the send, then "an assistant".
    static func thirdPersonSummary(on day: Date, in context: NSManagedObjectContext) -> String? {
        guard let send = latestSend(on: day, in: context) else { return nil }
        let name = send.sentBy == .leadGuide
            ? "the guide"
            : (ClassroomNames.name(forRecordName: send.sentByID, in: context) ?? send.sentByName ?? "an assistant")
        return send.summary(senderName: name, for: day, deadlineMinutes: settings(in: context)?.deadlineMinutes)
    }

    // MARK: - Settings

    /// The guide's settings as the share carries them, or nil before the guide
    /// has sent them (an older notebook, or before the first sync). A row from
    /// before schema 18 reads as email, at the default ParentLocker site.
    static func settings(in context: NSManagedObjectContext) -> Settings? {
        newestSettingsRow(in: context).map { row in
            Settings(
                isEnabled: row.isEnabled,
                toAddresses: row.toAddresses ?? "",
                nameOrder: row.nameOrderRaw.flatMap(AttendanceEmailNameOrder.init(rawValue:)) ?? .firstLast,
                groupByLevel: row.groupByLevel,
                deadlineMinutes: Int(row.deadlineMinutes),
                sendMethod: AttendanceSendMethod(stored: row.sendMethodRaw),
                parentLockerSite: parentLockerHost(row.parentLockerSite)
            )
        }
    }

    /// Writes the guide's settings into the share, as `Settings.shared` holds
    /// them (with ParentLocker picked, the email off). Only the lead guide
    /// may, and nothing is written when they already match. Returns whether
    /// anything changed; the caller saves.
    @discardableResult
    static func saveSettings(
        _ settings: Settings,
        role: CDClassroomMembership.ClassroomRole,
        now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> Bool {
        guard role == .leadGuide else { return false }
        let settings = settings.shared
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
        row.sendMethodRaw = settings.sendMethod.rawValue
        row.parentLockerSite = settings.parentLockerSite
        row.modifiedAt = now
        return true
    }

    /// Writes the guide's settings into the share only when it carries none
    /// yet. The launch's write: once a row exists, only the settings screen's
    /// edits change it (`saveSettings`), since a launch copied this device's
    /// preferences, which iCloud may not have brought up to date yet, over a
    /// newer edit made on another of the guide's devices (2026-10-05). It is
    /// dated `.distantPast`: a new device's first download can finish before
    /// the guide's row comes from the share, and the newest row wins, so these
    /// defaults must never outrank it (bug hunt 2026-10-13 afternoon, H1).
    /// Returns whether it wrote; the caller saves.
    @discardableResult
    static func saveSettingsIfMissing(
        _ settings: Settings,
        role: CDClassroomMembership.ClassroomRole,
        in context: NSManagedObjectContext
    ) -> Bool {
        guard role == .leadGuide else { return false }
        let request = CDFetchRequest(CDAttendanceEmailSettings.self)
        request.fetchLimit = 1
        guard context.safeFetchFirst(request) == nil else { return false }
        return saveSettings(settings, role: role, now: .distantPast, in: context)
    }

    private static func newestSettingsRow(in context: NSManagedObjectContext) -> CDAttendanceEmailSettings? {
        let request = CDFetchRequest(CDAttendanceEmailSettings.self)
        request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        request.fetchLimit = 1
        scopeToClassroom(request, in: context)
        return context.safeFetchFirst(request)
    }

    // MARK: - Stores

    /// In the Assistant, reads only the classroom share (the shared store),
    /// as the roll does (`AssistantDayRoll`): on an Apple Account that also
    /// keeps a notebook of its own, the private store holds that notebook's
    /// settings and sends, which would send her email to the wrong people or
    /// say it had gone. The notebook reads both stores (the guide's own
    /// records live in the private store); a single store reads everything.
    private static func scopeToClassroom<T>(_ request: NSFetchRequest<T>, in context: NSManagedObjectContext) {
        #if ASSISTANT_APP
        let shared = context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
        if let shared { request.affectedStores = [shared] }
        #endif
    }

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
