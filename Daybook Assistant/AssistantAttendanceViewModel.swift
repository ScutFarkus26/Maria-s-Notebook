import Foundation
import CoreData
import OSLog
import Observation

/// One day's roster paired with whatever attendance record exists for each
/// student, if any. The day starts as today and moves with the arrows or the
/// date picker, past or future.
///
/// Rows are *virtual* until marked: a student with no record yet shows as
/// unmarked without anything being inserted. Inserting a roster-wide set of
/// blank records on screen-open is what produced duplicate floods when two
/// devices opened the same day, and a third device would only make it worse.
@MainActor
@Observable
final class AssistantAttendanceViewModel {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DaybookAssistant",
        category: "attendance"
    )

    struct Row: Identifiable {
        let student: CDStudent
        var record: CDAttendanceRecord?
        var id: UUID { student.id ?? UUID() }
        var status: AttendanceStatus { record?.status ?? .unmarked }
        var absenceReason: AbsenceReason { record?.absenceReason ?? .none }
        /// The day's note, shared with the guide.
        var note: String { record?.note ?? "" }
    }

    /// Why there is no school on `date`, when there isn't.
    enum DayOff: Equatable {
        case weekend
        /// A day off in the guide's school calendar, with its reason if given.
        case holiday(String?)
    }

    private(set) var rows: [Row] = []
    private(set) var errorMessage: String?
    /// Set on weekends and on the guide's days off, which follow the notebook's
    /// school calendar (`SchoolDayChecker`): no marks are taken then.
    private(set) var dayOff: DayOff?
    /// Set when the guide has locked this day: its rows are read-only.
    private(set) var isLocked = false

    /// The day on screen (start of day).
    private(set) var date: Date
    private let context: NSManagedObjectContext
    private let container: NSPersistentCloudKitContainer?
    private let store: CDAttendanceStore
    /// Records created since the last save, to put into the classroom share
    /// once that save gives them permanent IDs.
    private var createdSinceSave: [CDAttendanceRecord] = []

    init(context: NSManagedObjectContext, container: NSPersistentCloudKitContainer?, date: Date = Date()) {
        self.context = context
        self.container = container
        self.date = Calendar.current.startOfDay(for: date)
        // The role is hardcoded rather than read from the membership row: this
        // app is only ever used by an assistant, and ClassroomPermissions is
        // what stops a mis-set membership from writing beyond attendance.
        self.store = CDAttendanceStore(context: context, role: .assistant)
    }

    /// Whether this day's marks can be changed: the role may write
    /// attendance, and the guide hasn't locked the day.
    var canMark: Bool {
        ClassroomPermissions.canWrite(entityName: "AttendanceRecord", role: .assistant) && !isLocked
    }

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// Shows `newDate` (any day, school or not), or reloads the current one.
    func load(_ newDate: Date? = nil) {
        if let newDate { date = Calendar.current.startOfDay(for: newDate) }
        dayOff = Self.dayOff(on: date, in: context)
        isLocked = store.isLocked(date)

        let request = CDFetchRequest(CDStudent.self)
        request.sortDescriptors = [
            NSSortDescriptor(key: "firstName", ascending: true),
            NSSortDescriptor(key: "lastName", ascending: true)
        ]
        let students = context.safeFetch(request).filter(\.isEnrolled)

        let records: [CDAttendanceRecord]
        do {
            records = try store.loadRecords(for: date).deduplicatedPerStudentDay()
        } catch {
            Self.logger.error("Loading attendance failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't load today's attendance."
            records = []
        }

        let byStudent = Dictionary(
            records.map { ($0.studentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        rows = students.map { student in
            Row(student: student, record: byStudent[student.id?.uuidString ?? ""])
        }
    }

    /// Advances one student through present → absent → tardy → left early and
    /// back to unmarked, creating the record on the first mark.
    func cycleStatus(for row: Row) {
        guard canMark else { return }
        do {
            guard let record = try store.ensureRecord(for: row.student, on: date) else { return }
            if record.isInserted { createdSinceSave.append(record) }
            _ = store.updateStatus(record, to: record.status.next())
            persist()
        } catch {
            Self.logger.error("Marking failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't save that mark."
        }
    }

    func setAbsenceReason(_ reason: AbsenceReason, for row: Row) {
        guard canMark, let record = row.record else { return }
        _ = store.updateAbsenceReason(record, to: reason)
        persist()
    }

    /// Writes the day's note for a student, creating the record if there is
    /// none yet. Empty text removes the note.
    func setNote(_ text: String?, for row: Row) {
        guard canMark else { return }
        do {
            guard let record = try store.ensureRecord(for: row.student, on: date) else { return }
            if record.isInserted { createdSinceSave.append(record) }
            guard store.updateNote(record, to: text) else { return }
            persist()
        } catch {
            Self.logger.error("Saving a note failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't save that note."
        }
    }

    // MARK: - Moving between days

    /// Moves to the next (`forward`) or previous school day, skipping weekends
    /// and the guide's days off. Stays put if none is found within a year.
    func step(forward: Bool) {
        if let next = SchoolDayChecker.schoolDay(from: date, forward: forward, using: context) {
            load(next)
        }
    }

    private static func dayOff(on date: Date, in context: NSManagedObjectContext) -> DayOff? {
        guard SchoolDayChecker.isNonSchoolDay(date, using: context) else { return nil }
        let request = CDFetchRequest(CDNonSchoolDay.self)
        request.predicate = NSPredicate(format: "date == %@", AppCalendar.startOfDay(date) as NSDate)
        request.fetchLimit = 1
        if let holiday = context.safeFetchFirst(request) {
            let reason = holiday.reason?.trimmed() ?? ""
            return .holiday(reason.isEmpty ? nil : reason)
        }
        return .weekend
    }

    private func persist() {
        guard context.safeSave() else {
            errorMessage = "Couldn't save. Your marks will retry when you're back online."
            return
        }
        errorMessage = nil
        // A new mark goes into the classroom share explicitly rather than
        // wherever Core Data would file it.
        let created = createdSinceSave.map(\.objectID)
        createdSinceSave = []
        if let container, !created.isEmpty {
            let context = self.context
            Task {
                await CDAttendanceStore.attachNewRecordsToClassroomShare(
                    created, container: container, pinContext: context
                )
            }
        }
        load()
    }
}
