import Foundation
import CoreData

// The day's sends of attendance to the school (`CDAttendanceEmailSend`):
// read, recorded, and worded for MCP, and the two notes that travel as one
// of these but are never read as a send: ParentLocker isn't expecting a
// day's attendance, and arrival closed. Compiled into both apps.

extension AttendanceEmailLog {

    /// The `channelRaw` of a note, not a send: ParentLocker said it isn't
    /// expecting the class's attendance that day (bug hunt 2026-10-13
    /// afternoon, M8). A record of the same type, so it reaches every device
    /// of the class through the share with no schema change. Only the
    /// reminder and the ParentLocker line read it (`isNotExpected`): every
    /// read of the day's sends leaves it out (`sends`, `latestSend`), so it
    /// never shows as "Sent…", never counts as the day's send and never
    /// makes the day "after". An Assistant build from before schema 18 reads
    /// it as an email that went, as it reads every ParentLocker send.
    nonisolated static let notExpectedChannel = "notExpected"

    /// The `channelRaw` of the other note: arrival closed on the day, at the
    /// row's `sentAt` (domain-logic review A1). Written once a day where
    /// arrival closes (`recordArrivalClosed`: the notebook's Close Arrival
    /// and its Undo of a Reset Day, the Assistant's Close Arrival and Siri's),
    /// and taken back on every way back to Arrival (`deleteArrivalClosedNotes`:
    /// Undo, Reopen, Siri's Undo, Reset Day). No read of the day's sends
    /// counts it, and it closes no day by itself: the Late rule only takes
    /// the close's time from it (`arrivalClosedAt`), and whether the day
    /// reads closed still comes from its records (plan "Tide list clean-up
    /// 2026-11", D3). Builds from schema 25 on read it this way; one from
    /// before would show it as an email that went.
    nonisolated static let arrivalClosedChannel = "arrivalClosed"

    /// The channels that mark a note, not a send.
    nonisolated static let noteChannels = [notExpectedChannel, arrivalClosedChannel]

    /// The day's records of this type: its sends, and with `notes`, its
    /// notes too. A row with no channel at all is a send. Matched by the
    /// day's range, not its exact midnight (`AppCalendar.dayPredicate`).
    private static func recordsRequest(on day: Date, notes: Bool) -> NSFetchRequest<CDAttendanceEmailSend> {
        let request = CDFetchRequest(CDAttendanceEmailSend.self)
        let onDay = AppCalendar.dayPredicate(on: day)
        let sendsOnly = NSPredicate(format: "channelRaw == nil OR NOT (channelRaw IN %@)", noteChannels)
        request.predicate = notes ? onDay : NSCompoundPredicate(andPredicateWithSubpredicates: [onDay, sendsOnly])
        return request
    }

    /// The day's sends, newest first.
    static func sends(on day: Date, in context: NSManagedObjectContext) -> [CDAttendanceEmailSend] {
        let request = recordsRequest(on: day, notes: false)
        request.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: false)]
        scopeToClassroom(request, in: context)
        return context.safeFetch(request)
    }

    /// The newest send for `day`, if the email has gone.
    static func latestSend(on day: Date, in context: NSManagedObjectContext) -> Send? {
        let request = recordsRequest(on: day, notes: false)
        request.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: false)]
        request.fetchLimit = 1
        scopeToClassroom(request, in: context)
        return context.safeFetchFirst(request).map(Send.init)
    }

    /// The day's sends as its summary line words them (bug hunt 2026-10-20,
    /// #15). Who sent it, and whether it was on time, come from the first
    /// send the way the newest went, so Send Again, or a second assistant's
    /// send, no longer relabels an on-time email "(late)" or changes who sent
    /// it for everyone; a later send of that way shows as "· sent again
    /// 10:15 AM". Whether the day has gone is still `latestSend`'s.
    struct DaySends: Equatable, Sendable {
        /// The day's first send by the way the newest went.
        let first: Send
        /// The newest send, when that way went more than once.
        let again: Send?

        /// "Emailed 8:42 AM by Sarah · sent again 10:15 AM". `senderName`
        /// is `first`'s, as `Send.senderName` reads it.
        func summary(
            senderName: String, for day: Date, deadlineMinutes: Int? = nil, calendar: Calendar = AppCalendar.shared
        ) -> String {
            let line = first.summary(
                senderName: senderName, for: day, deadlineMinutes: deadlineMinutes, calendar: calendar
            )
            guard let again else { return line }
            return line + " · sent again " + Send.time(again.sentAt, reporting: day, calendar: calendar)
        }
    }

    /// The day's sends for its summary line, or nil before any has gone:
    /// the first and the newest of the way the newest went.
    static func daySends(on day: Date, in context: NSManagedObjectContext) -> DaySends? {
        daySends(newestFirst: sends(on: day, in: context).map(Send.init))
    }

    /// `daySends` from the day's sends, newest first.
    static func daySends(newestFirst: [Send]) -> DaySends? {
        guard let latest = newestFirst.first else { return nil }
        let sameWay = newestFirst.filter { $0.channel == latest.channel }
        guard let first = sameWay.last else { return nil }
        return DaySends(first: first, again: sameWay.count > 1 ? latest : nil)
    }

    /// What a screen shows of a day, in one read of its records (bug hunt
    /// 2026-11-03 #18): the newest send (`latestSend`'s), the summary line's
    /// sends (`daySends`'s) and whether ParentLocker said it isn't expecting
    /// the day (`isNotExpected`'s).
    struct DayRecords: Equatable, Sendable {
        /// The day's sends, newest first, the note left out.
        let sends: [Send]
        let isNotExpected: Bool

        var latestSend: Send? { sends.first }
        var daySends: DaySends? { AttendanceEmailLog.daySends(newestFirst: sends) }
    }

    static func dayRecords(on day: Date, in context: NSManagedObjectContext) -> DayRecords {
        let request = recordsRequest(on: day, notes: true)
        request.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: false)]
        scopeToClassroom(request, in: context)
        let records = context.safeFetch(request)
        return DayRecords(
            sends: records.filter { !noteChannels.contains($0.channelRaw) }.map(Send.init),
            isNotExpected: records.contains { $0.channelRaw == notExpectedChannel }
        )
    }

    /// The channels of the day's records, the "not expected" note's
    /// included: what the ParentLocker sync reads of a day in one go.
    static func channels(on day: Date, in context: NSManagedObjectContext) -> Set<String> {
        let request = recordsRequest(on: day, notes: true)
        scopeToClassroom(request, in: context)
        return Set(context.safeFetch(request).map { $0.channelRaw })
    }

    /// ParentLocker said it isn't expecting the class's attendance on `day`,
    /// on this device or another (`notExpectedChannel`).
    static func isNotExpected(on day: Date, in context: NSManagedObjectContext) -> Bool {
        let request = noteRequest(notExpectedChannel, on: day)
        request.fetchLimit = 1
        scopeToClassroom(request, in: context)
        return context.safeFetchFirst(request) != nil
    }

    /// When arrival closed on `day`, by the day's `arrivalClosedChannel` note
    /// (the earliest, should two devices each write one), or nil without one.
    static func arrivalClosedAt(on day: Date, in context: NSManagedObjectContext) -> Date? {
        let request = noteRequest(arrivalClosedChannel, on: day)
        scopeToClassroom(request, in: context)
        return context.safeFetch(request).compactMap(\.sentAt).min()
    }

    private static func noteRequest(_ channel: String, on day: Date) -> NSFetchRequest<CDAttendanceEmailSend> {
        let request = CDFetchRequest(CDAttendanceEmailSend.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            AppCalendar.dayPredicate(on: day), NSPredicate(format: "channelRaw == %@", channel)
        ])
        return request
    }

    // MARK: - Changed since reported

    /// The marks changed on a day after the school was last told (domain-logic
    /// review R18): the 9:00 email says Maya is absent, she comes in at 10:30,
    /// and the school's copy is now wrong. Worked out, never stored.
    struct ChangesSinceReported: Equatable, Sendable {
        /// How many children's records changed after the send.
        let count: Int
        /// The day's latest send, which they changed after.
        let send: Send

        /// "2 changes since 9:02 AM".
        func summary(for day: Date, calendar: Calendar = AppCalendar.shared) -> String {
            let changes = count == 1 ? "1 change" : "\(count) changes"
            return "\(changes) since \(Send.time(send.sentAt, reporting: day, calendar: calendar))"
        }

        /// The line both apps and Claude show: "2 changes since 9:02 AM ·
        /// Send an update". ParentLocker takes only the day's own marks, so a
        /// day behind it is put right there by hand.
        func line(for day: Date, calendar: Calendar = AppCalendar.shared) -> String {
            let action = send.channel == .parentLocker ? "Update it in ParentLocker" : "Send an update"
            return summary(for: day, calendar: calendar) + " · " + action
        }
    }

    /// The children whose record on `day` changed after the day's latest
    /// send (`modifiedAt`, which every mark, reason, note and pickup stamps),
    /// or nil when nothing was sent or nothing changed since. One record per
    /// child, the one the grid shows (`deduplicatedPerStudentDay`). Today's
    /// ParentLocker send is left out: ParentLocker follows today's marks as
    /// they change.
    static func changesSinceReported(
        on day: Date, now: Date = Date(), in context: NSManagedObjectContext
    ) -> ChangesSinceReported? {
        guard let send = latestSend(on: day, in: context) else { return nil }
        if send.channel == .parentLocker, AppCalendar.isSameDay(day, now) { return nil }
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = AppCalendar.dayPredicate(on: day)
        scopeToClassroom(request, in: context)
        let changed = context.safeFetch(request).deduplicatedPerStudentDay()
            .filter { ($0.modifiedAt ?? .distantPast) > send.sentAt }
        return changed.isEmpty ? nil : ChangesSinceReported(count: changed.count, send: send)
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
        let send = record(on: day, role: role, channelRaw: channel.rawValue, now: now, in: context)
        send.wasConfirmedByHand = confirmedByHand
        return send
    }

    /// Notes that ParentLocker isn't expecting the class's attendance on
    /// `day` (`notExpectedChannel`), stamped as a send is. The caller saves,
    /// and in the Assistant puts the new record into the share.
    @discardableResult
    static func recordNotExpected(
        on day: Date,
        role: CDClassroomMembership.ClassroomRole,
        now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> CDAttendanceEmailSend {
        record(on: day, role: role, channelRaw: notExpectedChannel, now: now, in: context)
    }

    /// Notes that arrival closed on `day`, at `now` (`arrivalClosedChannel`),
    /// stamped as a send is. One note a day: a day that already has one,
    /// from this device or another, gets none, and nil comes back (two
    /// devices that each write one before they sync leave two, and the
    /// reader takes the earlier). Nil too when `role` may not write the
    /// class's records (an assistant added as View only). The caller saves,
    /// and in the Assistant puts the new record into the share.
    @discardableResult
    static func recordArrivalClosed(
        on day: Date,
        role: CDClassroomMembership.ClassroomRole,
        now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> CDAttendanceEmailSend? {
        guard ClassroomPermissions.canWrite(entityName: noteEntityName, role: role),
              arrivalClosedAt(on: day, in: context) == nil else { return nil }
        return record(on: day, role: role, channelRaw: arrivalClosedChannel, now: now, in: context)
    }

    /// Takes back every arrival-closed note on `day`, whoever wrote it, as
    /// `arrivalClosedAt` reads them (in the Assistant, the classroom share's
    /// only). Returns how many; none when `role` may not delete the class's
    /// records (an assistant added as View only). The caller saves. A
    /// delete that never reaches another device leaves it a note that only
    /// dates a close: it never closes the day there.
    @discardableResult
    static func deleteArrivalClosedNotes(
        on day: Date,
        role: CDClassroomMembership.ClassroomRole,
        in context: NSManagedObjectContext
    ) -> Int {
        guard ClassroomPermissions.canDelete(entityName: noteEntityName, role: role) else { return 0 }
        let request = noteRequest(arrivalClosedChannel, on: day)
        scopeToClassroom(request, in: context)
        let notes = context.safeFetch(request)
        notes.forEach(context.delete)
        return notes.count
    }

    /// The notes' entity, as the permission matrix names it.
    private static let noteEntityName = "AttendanceEmailSend"

    private static func record(
        on day: Date,
        role: CDClassroomMembership.ClassroomRole,
        channelRaw: String,
        now: Date,
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
        send.channelRaw = channelRaw
        return send
    }

    /// The day's send as someone outside the classroom reads it ("Emailed
    /// 8:42 AM by Sarah (late)", the guide's own "by the guide"), for MCP,
    /// from the day's first send, with any later one as "· sent again"
    /// (`DaySends`). An assistant is named as she goes by now (the
    /// classroom's list, by the send's record name, so a rename reaches old
    /// sends), then by the name stamped on the send, then "an assistant".
    static func thirdPersonSummary(on day: Date, in context: NSManagedObjectContext) -> String? {
        guard let sends = daySends(on: day, in: context) else { return nil }
        let send = sends.first
        let name = send.sentBy == .leadGuide
            ? "the guide"
            : (ClassroomNames.name(forRecordName: send.sentByID, in: context) ?? send.sentByName ?? "an assistant")
        return sends.summary(senderName: name, for: day, deadlineMinutes: settings(in: context)?.deadlineMinutes)
    }
}

// MARK: - The arrival-closed note, on a day this store may write

extension CDAttendanceStore {

    /// `AttendanceEmailLog.recordArrivalClosed` as this store's role, on a
    /// day it may write: none on a locked day, as no mark goes on one. The
    /// caller saves.
    @discardableResult
    func recordArrivalClosed(on day: Date, now: Date = Date()) -> CDAttendanceEmailSend? {
        guard canWrite(on: day) else { return nil }
        return AttendanceEmailLog.recordArrivalClosed(on: day, role: role, now: now, in: context)
    }

    /// `AttendanceEmailLog.deleteArrivalClosedNotes` as this store's role, on
    /// a day it may write: a locked day keeps its note, as it keeps its
    /// marks. Returns how many it deleted. The caller saves.
    @discardableResult
    func deleteArrivalClosedNotes(on day: Date) -> Int {
        guard canWrite(on: day) else { return 0 }
        return AttendanceEmailLog.deleteArrivalClosedNotes(on: day, role: role, in: context)
    }
}
