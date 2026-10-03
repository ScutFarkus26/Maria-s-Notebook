//
//  SiriAttendance.swift
//  Cosmic Daybook
//
//  What the attendance intents share, in both apps: open the store through
//  `SiriHost`, mark through `CDAttendanceStore` (the chokepoint every grid tap
//  goes through, so permissions, locked days and attribution are the same),
//  save, and remember the change so "Undo that" can put it back.
//
//  Shared with Daybook Assistant, which compiles this file by path.
//

import AppIntents
import CoreData
import OSLog

@MainActor
struct SiriAttendance {

    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CosmicDaybook",
        category: "SiriAttendance"
    )

    let stack: CoreDataStack
    let store: CDAttendanceStore
    /// Siri marks today only.
    let today: Date

    var context: NSManagedObjectContext { stack.viewContext }

    init() throws {
        let stack = try Self.openStack()
        try SiriHost.checkReady(in: stack.viewContext)
        self.init(stack: stack, role: SiriHost.role)
    }

    /// The app's store, or Siri's plain "couldn't open your class"
    /// (`SiriHost.cannotOpenMessage`): the store's own error is raw system
    /// text, so it goes to the log. The student lookups open it this way too.
    static func openStack() throws -> CoreDataStack {
        do {
            return try SiriHost.stack()
        } catch {
            log(error, while: "opening the class")
            throw SiriAttendanceError.cannotOpen
        }
    }

    /// Siri's own errors speak for themselves; anything else (a database
    /// error, say) would reach Siri as raw system text, so it becomes the
    /// plain "Something went wrong saving attendance" and the raw error goes
    /// to the log. Siri's confirmation prompts are never wrapped: their
    /// cancellation must reach Siri as it is.
    nonisolated static func plain(_ error: Error, while activity: String = "changing attendance") -> Error {
        if error is SiriAttendanceError { return error }
        log(error, while: activity)
        return SiriAttendanceError.saveFailed
    }

    /// Runs `work`, translating any error that isn't Siri's own (`plain`).
    static func plainly<T>(_ activity: String, _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            throw plain(error, while: activity)
        }
    }

    nonisolated private static func log(_ error: Error, while activity: String) {
        let ns = error as NSError
        logger.error("""
            Siri attendance failed while \(activity, privacy: .public): \
            \(ns.domain, privacy: .public) \(ns.code, privacy: .public) \(ns.localizedDescription, privacy: .public)
            """)
    }

    /// Tests pass an in-memory stack and a fixed day.
    init(stack: CoreDataStack, role: CDClassroomMembership.ClassroomRole?, today: Date = Date()) {
        self.stack = stack
        store = CDAttendanceStore(context: stack.viewContext, role: role)
        self.today = Calendar.current.startOfDay(for: today)
    }

    var isSchoolDay: Bool {
        !SchoolDayChecker.isNonSchoolDay(today, using: context)
    }

    /// The child `entity` names, if she's on today's roll as the grid shows
    /// it (`AttendanceRoster`): a child who hasn't started yet or has left is
    /// refused rather than marked, and one whose last day is today is not.
    func student(for entity: StudentEntity) throws -> CDStudent {
        guard let student = context.object(CDStudent.self, id: entity.id) else {
            throw SiriAttendanceError.studentNotFound(entity.fullName)
        }
        let records = AttendanceRoster.recordStudentIDs(on: today, in: context)
        guard !AttendanceRoster.students(on: today, from: [student], recordStudentIDs: records).isEmpty else {
            throw student.isEnrolled
                ? SiriAttendanceError.notStarted(student.fullName)
                : SiriAttendanceError.notEnrolled(student.fullName)
        }
        return student
    }

    /// The children Siri matches a spoken name against: everyone enrolled
    /// (so a child who hasn't started is refused by name, not "not found"),
    /// and a departed child while she's still on `day`'s roll. Both apps'
    /// `SiriHost.roster` narrow their class through this.
    static func nameable(
        _ students: [CDStudent], on day: Date = Date(), in context: NSManagedObjectContext
    ) -> [CDStudent] {
        let start = Calendar.current.startOfDay(for: day)
        let records = AttendanceRoster.recordStudentIDs(on: start, in: context)
        let onRoll = AttendanceRoster.students(on: start, from: students, recordStudentIDs: records)
        let onRollIDs = Set(onRoll.map(\.objectID))
        return students.filter { $0.isEnrolled || onRollIDs.contains($0.objectID) }
    }

    /// Asks before marking on a weekend or a day off: a mark there is almost
    /// always a slip, but a school event on a Saturday is a real one.
    static func confirmIfNoSchool(
        _ session: SiriAttendance, marking name: String, for intent: some AppIntent
    ) async throws {
        guard !session.isSchoolDay else { return }
        try await intent.requestConfirmation(
            dialog: "Today isn't a school day. Mark \(name) anyway?"
        )
    }

    /// How Siri names `student` in its answers: in full in the notebook, as
    /// the grid does in the Assistant (`SiriHost.displayNames`).
    func spokenName(for student: CDStudent) -> String {
        SiriHost.displayNames(for: SiriHost.roster(in: context))[student.objectID] ?? student.fullName
    }

    /// `student`'s mark today, without creating a record to read it.
    func status(of student: CDStudent) throws -> AttendanceStatus {
        let key = student.id?.uuidString ?? ""
        do {
            return try store.loadRecords(for: today)
                .filter { $0.studentID == key }
                .deduplicatedPerStudentDay()
                .first?.status ?? .unmarked
        } catch {
            throw Self.plain(error, while: "reading a mark")
        }
    }

    /// Sets `student`'s mark for today and returns what it was before.
    @discardableResult
    /// `reason` applies to Absent only; nil leaves the reason as it is. A new
    /// reason on a child already absent is a change of its own.
    func mark(
        _ student: CDStudent, as status: AttendanceStatus, reason: AbsenceReason? = nil
    ) async throws -> AttendanceStatus {
        try await Self.plainly("marking attendance") {
            try await markUnwrapped(student, as: status, reason: reason)
        }
    }

    private func markUnwrapped(
        _ student: CDStudent, as status: AttendanceStatus, reason: AbsenceReason?
    ) async throws -> AttendanceStatus {
        guard !store.isLocked(today) else { throw SiriAttendanceError.dayLocked }
        guard let record = try store.ensureRecord(for: student, on: today) else {
            throw SiriAttendanceError.cannotMark
        }
        let previous = record.status
        let previousReasonRaw = record.absenceReasonRaw
        let before = AttendanceRecordSnapshot(record).values
        let created = record.isInserted ? [record] : []
        let statusChanges = previous != status
        if statusChanges {
            guard store.updateStatus(record, to: status) else { throw SiriAttendanceError.cannotMark }
        }
        let reasonChanges = status == .absent && reason.map { store.updateAbsenceReason(record, to: $0) } == true
        guard statusChanges || reasonChanges else { return previous }
        var pending = Pending(record: record, from: previous, to: status, before: before)
        if reasonChanges {
            pending.fromReasonRaw = previousReasonRaw
            pending.toReasonRaw = record.absenceReasonRaw
        }
        let name = spokenName(for: student)
        try await commit([pending], created: created, summary: "\(name) \(status.spokenWord)", name: name)
        return previous
    }

    /// "Here": present, or late once arrival has closed in the Assistant
    /// (`SiriHost.statusForHere`), but never a downgrade: a child already
    /// present stays present, as a tap on the grid leaves her.
    func markHere(_ student: CDStudent) async throws -> (previous: AttendanceStatus, now: AttendanceStatus) {
        var status = SiriHost.statusForHere(on: today, store: store)
        if status == .tardy, try self.status(of: student) == .present {
            status = .present
        }
        return (try await mark(student, as: status), status)
    }

    /// A mark made in the context and not yet saved.
    struct Pending {
        let record: CDAttendanceRecord
        let from: AttendanceStatus
        let to: AttendanceStatus
        /// The stored reason before and after, when the mark set one.
        var fromReasonRaw: String?
        var toReasonRaw: String?
        /// The whole record before the mark, for an Undo that puts back its
        /// times too. Nil for Close Arrival's marks.
        var before: AttendanceRecordSnapshot.Values?
    }

    /// Saves the marks just made, remembers them for Undo, and sends them on
    /// their way to iCloud without holding up Siri's answer.
    func commit(
        _ marks: [Pending],
        created: [CDAttendanceRecord],
        summary: String,
        name: String? = nil,
        closedArrival: Bool = false
    ) async throws {
        // Watch for the export before saving, so a quick one isn't missed.
        let exportWatch = SiriExportWatch()
        guard context.safeSave() else {
            exportWatch.stop()
            discard(marks, created: created)
            throw SiriAttendanceError.saveFailed
        }
        // After the save: a new record's ID is only permanent from here.
        SiriAttendanceChange(
            day: today,
            marks: marks.map { mark in
                SiriAttendanceChange.Mark(
                    recordURI: mark.record.objectID.uriRepresentation(), from: mark.from, to: mark.to,
                    fromReasonRaw: mark.fromReasonRaw, toReasonRaw: mark.toReasonRaw,
                    before: mark.before, after: mark.before.map { _ in AttendanceRecordSnapshot(mark.record).values }
                )
            },
            summary: summary,
            closedArrival: closedArrival,
            name: name
        ).remember()

        let createdIDs = created.map(\.objectID)
        let stack = self.stack
        SiriSyncKeepAlive.run {
            await SiriHost.didSave(created: createdIDs, in: stack)
            await exportWatch.wait(upTo: .seconds(20))
        }
        NotificationCenter.default.post(name: .attendanceChangedBySiri, object: nil)
        Self.logger.notice("Siri marked attendance: \(marks.count, privacy: .public) record(s)")
    }

    /// A failed save leaves the marks in the context, where the next save (a
    /// grid tap's) would send them on quietly: not remembered for Undo, and
    /// never attached to the classroom share. Put them back instead.
    private func discard(_ marks: [Pending], created: [CDAttendanceRecord]) {
        let createdIDs = Set(created.map(\.objectID))
        for record in created { context.delete(record) }
        for mark in marks where !createdIDs.contains(mark.record.objectID) {
            context.refresh(mark.record, mergeChanges: false)
        }
    }

    /// Puts back the last change Siri made today, where nothing has changed
    /// those marks since. Returns what Siri says about it
    /// (`SiriAttendanceChange.undoneDialog`).
    ///
    /// The change is forgotten only once the undo is saved, so a failed save
    /// can be retried, and a locked day refuses the undo and keeps it (it
    /// used to find nothing it could change, and forget it). A Close Arrival
    /// that found everyone marked has no marks to put back, and undoing it
    /// just reopens arrival.
    func undoLast() async throws -> String {
        try await Self.plainly("undoing a mark") { try await undoLastUnwrapped() }
    }

    private func undoLastUnwrapped() async throws -> String {
        guard let change = SiriAttendanceChange.last(), Calendar.current.isDate(change.day, inSameDayAs: today) else {
            throw SiriAttendanceError.nothingToUndo
        }
        guard !store.isLocked(today) else { throw SiriAttendanceError.dayLocked }
        guard let coordinator = context.persistentStoreCoordinator else { throw SiriAttendanceError.saveFailed }

        var reverted: [Pending] = []
        for mark in change.marks {
            guard let id = coordinator.managedObjectID(forURIRepresentation: mark.recordURI),
                  let record = try? context.existingObject(with: id) as? CDAttendanceRecord,
                  undo(mark, on: record) else { continue }
            reverted.append(Pending(record: record, from: mark.to, to: mark.from))
        }
        if reverted.isEmpty, !change.marks.isEmpty {
            SiriAttendanceChange.forget()
            if change.closedArrival { reopenArrival() }
            throw SiriAttendanceError.changedSince(change.changedSinceDialog)
        }
        if !reverted.isEmpty {
            try await commit(reverted, created: [], summary: "undo of \(change.summary)")
        }
        if change.closedArrival { reopenArrival() }
        // An undo is not itself undoable: "Undo that" twice shouldn't flip back.
        SiriAttendanceChange.forget()
        return change.undoneDialog
    }

    /// Puts one remembered mark back, if nothing has changed it since: the
    /// whole record as it was, times and all, as ⌘Z on the roll does
    /// (`CDAttendanceStore.revert`). Re-marking the old status instead gave
    /// a child present since 8:05 a new arrival time, and a child who had
    /// left early came back with no arrival and today's departure.
    ///
    /// A change remembered without the record (before 2026-10-03, or Close
    /// Arrival's) puts back its status, and the reason it set. A
    /// reason-only change ("absent, sick" on a child already absent) has the
    /// same status before and after, so only the reason goes back.
    private func undo(_ mark: SiriAttendanceChange.Mark, on record: CDAttendanceRecord) -> Bool {
        if let before = mark.before, let after = mark.after {
            return store.revert(
                record,
                to: AttendanceRecordSnapshot(objectID: record.objectID, values: before),
                ifStill: AttendanceRecordSnapshot(objectID: record.objectID, values: after)
            )
        }
        guard record.status == mark.to else { return false }
        if let toRaw = mark.toReasonRaw, record.absenceReasonRaw != toRaw { return false }
        var changed = false
        if mark.from != mark.to {
            guard store.updateStatus(record, to: mark.from) else { return false }
            changed = true
        }
        if let fromRaw = mark.fromReasonRaw, store.restoreAbsenceReason(record, toRaw: fromRaw) {
            changed = true
        }
        return changed
    }

    /// Back to arrival, and an open grid shows it.
    private func reopenArrival() {
        SiriHost.arrivalReopened(on: today)
        NotificationCenter.default.post(name: .attendanceChangedBySiri, object: nil)
    }
}

// MARK: - Errors

enum SiriAttendanceError: Error, CustomLocalizedStringResourceConvertible {
    case studentNotFound(String)
    case notEnrolled(String)
    case notStarted(String)
    case dayLocked
    case cannotMark
    case saveFailed
    case notReady(String)
    case cannotOpen
    case nothingToUndo
    /// Carries the whole sentence (`SiriAttendanceChange.changedSinceDialog`).
    case changedSince(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .studentNotFound(let name):
            return "I couldn't find \(name) in your class."
        case .notEnrolled(let name):
            return "\(name) isn't in the class anymore, so I didn't mark attendance."
        case .notStarted(let name):
            return "\(name) hasn't started yet, so I didn't mark attendance."
        case .dayLocked:
            return "Today's attendance is locked, so I can't change it."
        case .cannotMark:
            return "That child's attendance can't be changed from here. Open the app to mark it."
        case .saveFailed:
            return "Something went wrong saving attendance. Try again."
        case .notReady(let message):
            return "\(message)"
        case .cannotOpen:
            return "\(SiriHost.cannotOpenMessage)"
        case .nothingToUndo:
            return "There's no attendance mark from Siri today to undo."
        case .changedSince(let dialog):
            return "\(dialog)"
        }
    }
}
