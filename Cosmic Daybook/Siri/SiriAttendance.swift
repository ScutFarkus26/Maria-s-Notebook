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
        let stack = try SiriHost.stack()
        try SiriHost.checkReady(in: stack.viewContext)
        self.init(stack: stack, role: SiriHost.role)
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
        return try store.loadRecords(for: today)
            .filter { $0.studentID == key }
            .deduplicatedPerStudentDay()
            .first?.status ?? .unmarked
    }

    /// Sets `student`'s mark for today and returns what it was before.
    @discardableResult
    /// `reason` applies to Absent only; nil leaves the reason as it is. A new
    /// reason on a child already absent is a change of its own.
    func mark(
        _ student: CDStudent, as status: AttendanceStatus, reason: AbsenceReason? = nil
    ) async throws -> AttendanceStatus {
        guard !store.isLocked(today) else { throw SiriAttendanceError.dayLocked }
        guard let record = try store.ensureRecord(for: student, on: today) else {
            throw SiriAttendanceError.cannotMark
        }
        let previous = record.status
        let previousReasonRaw = record.absenceReasonRaw
        let created = record.isInserted ? [record] : []
        let statusChanges = previous != status
        if statusChanges {
            guard store.updateStatus(record, to: status) else { throw SiriAttendanceError.cannotMark }
        }
        let reasonChanges = status == .absent && reason.map { store.updateAbsenceReason(record, to: $0) } == true
        guard statusChanges || reasonChanges else { return previous }
        var pending = Pending(record: record, from: previous, to: status)
        if reasonChanges {
            pending.fromReasonRaw = previousReasonRaw
            pending.toReasonRaw = record.absenceReasonRaw
        }
        try await commit(
            [pending],
            created: created,
            summary: "\(spokenName(for: student)) \(status.displayName.lowercased())"
        )
        return previous
    }

    /// "Here": present, or tardy once arrival has closed in the Assistant
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
    }

    /// Saves the marks just made, remembers them for Undo, and sends them on
    /// their way to iCloud without holding up Siri's answer.
    func commit(
        _ marks: [Pending],
        created: [CDAttendanceRecord],
        summary: String,
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
            marks: marks.map {
                SiriAttendanceChange.Mark(
                    recordURI: $0.record.objectID.uriRepresentation(), from: $0.from, to: $0.to,
                    fromReasonRaw: $0.fromReasonRaw, toReasonRaw: $0.toReasonRaw
                )
            },
            summary: summary,
            closedArrival: closedArrival
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
    /// those marks since. Returns what was undone.
    ///
    /// The change is forgotten only once the undo is saved, so a failed save
    /// can be retried, and a locked day refuses the undo and keeps it (it
    /// used to find nothing it could change, and forget it). A Close Arrival
    /// that found everyone marked has no marks to put back, and undoing it
    /// just reopens arrival.
    func undoLast() async throws -> String {
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
            throw SiriAttendanceError.changedSince(change.summary)
        }
        if !reverted.isEmpty {
            try await commit(reverted, created: [], summary: "undo of \(change.summary)")
        }
        if change.closedArrival { reopenArrival() }
        // An undo is not itself undoable: "Undo that" twice shouldn't flip back.
        SiriAttendanceChange.forget()
        return change.summary
    }

    /// Puts one remembered mark back, if nothing has changed it since: its
    /// status, and the reason it set. A reason-only change ("absent, sick"
    /// on a child already absent) has the same status before and after, so
    /// only the reason goes back; it used to count as "changed since".
    private func undo(_ mark: SiriAttendanceChange.Mark, on record: CDAttendanceRecord) -> Bool {
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
    case nothingToUndo
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
            return "Attendance can't be changed from here."
        case .saveFailed:
            return "Something went wrong saving attendance. Please try again."
        case .notReady(let message):
            return "\(message)"
        case .nothingToUndo:
            return "There's no attendance mark from Siri today to undo."
        case .changedSince(let summary):
            return "The marks from \(summary) have changed since, so I left them."
        }
    }
}
