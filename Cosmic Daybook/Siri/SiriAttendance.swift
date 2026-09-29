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

    /// The current child `entity` names. A former student is refused rather
    /// than marked: she has no place on today's roll.
    func student(for entity: StudentEntity) throws -> CDStudent {
        guard let student = context.object(CDStudent.self, id: entity.id) else {
            throw SiriAttendanceError.studentNotFound(entity.fullName)
        }
        guard student.isEnrolled else {
            throw SiriAttendanceError.notEnrolled(student.fullName)
        }
        return student
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
    func mark(_ student: CDStudent, as status: AttendanceStatus) async throws -> AttendanceStatus {
        guard !store.isLocked(today) else { throw SiriAttendanceError.dayLocked }
        guard let record = try store.ensureRecord(for: student, on: today) else {
            throw SiriAttendanceError.cannotMark
        }
        let previous = record.status
        guard previous != status else { return previous }
        let created = record.isInserted ? [record] : []
        guard store.updateStatus(record, to: status) else { throw SiriAttendanceError.cannotMark }
        try await commit(
            [Pending(record: record, from: previous, to: status)],
            created: created,
            summary: "\(student.fullName) \(status.displayName.lowercased())"
        )
        return previous
    }

    /// A mark made in the context and not yet saved.
    struct Pending {
        let record: CDAttendanceRecord
        let from: AttendanceStatus
        let to: AttendanceStatus
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
            throw SiriAttendanceError.saveFailed
        }
        // After the save: a new record's ID is only permanent from here.
        SiriAttendanceChange(
            day: today,
            marks: marks.map {
                SiriAttendanceChange.Mark(recordURI: $0.record.objectID.uriRepresentation(), from: $0.from, to: $0.to)
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

    /// Puts back the last change Siri made today, where nothing has changed
    /// those marks since. Returns what was undone.
    func undoLast() async throws -> String {
        guard let change = SiriAttendanceChange.last(), Calendar.current.isDate(change.day, inSameDayAs: today) else {
            throw SiriAttendanceError.nothingToUndo
        }
        SiriAttendanceChange.forget()
        guard let coordinator = context.persistentStoreCoordinator else { throw SiriAttendanceError.saveFailed }

        var reverted: [Pending] = []
        for mark in change.marks {
            guard let id = coordinator.managedObjectID(forURIRepresentation: mark.recordURI),
                  let record = try? context.existingObject(with: id) as? CDAttendanceRecord,
                  record.status == mark.to,
                  store.updateStatus(record, to: mark.from) else { continue }
            reverted.append(Pending(record: record, from: mark.to, to: mark.from))
        }
        if change.closedArrival {
            SiriHost.arrivalReopened(on: today)
        }
        guard !reverted.isEmpty else {
            if change.closedArrival { NotificationCenter.default.post(name: .attendanceChangedBySiri, object: nil) }
            throw SiriAttendanceError.changedSince(change.summary)
        }
        try await commit(reverted, created: [], summary: "undo of \(change.summary)")
        // An undo is not itself undoable: "Undo that" twice shouldn't flip back.
        SiriAttendanceChange.forget()
        return change.summary
    }
}

// MARK: - Errors

enum SiriAttendanceError: Error, CustomLocalizedStringResourceConvertible {
    case studentNotFound(String)
    case notEnrolled(String)
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
            return "\(name) isn't in the class any more, so I didn't mark attendance."
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
