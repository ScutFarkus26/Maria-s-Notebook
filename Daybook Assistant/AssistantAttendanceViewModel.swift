import Foundation
import CoreData
import OSLog
import Observation

/// One day's roster paired with whatever attendance record exists for each
/// student, if any. The day starts as today and moves with the arrows or the
/// date picker, past or future.
///
/// A morning runs in two phases. During **Arrival** a tap marks a child
/// present; switching to **Late** marks everyone still unmarked absent, and a
/// tap then turns an absent child tardy. Tapping again undoes the last tap.
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

    /// The record's values are copied in when the day loads, not read through
    /// it: a tile handed the same record object after its status changed would
    /// look unchanged to SwiftUI and keep its old colour.
    struct Row: Identifiable {
        let student: CDStudent
        let id: UUID
        let status: AttendanceStatus
        let absenceReason: AbsenceReason
        /// The day's note, shared with the guide.
        let note: String
        /// When the current mark was made; nil while unmarked.
        let markedAt: Date?

        init(student: CDStudent, record: CDAttendanceRecord?) {
            self.student = student
            self.id = student.id ?? UUID()
            self.status = record?.status ?? .unmarked
            self.absenceReason = record?.absenceReason ?? .none
            self.note = record?.note ?? ""
            self.markedAt = record?.markedAt
        }
    }

    /// Which part of the morning the taps are for.
    enum Phase: Equatable {
        /// Children are arriving: a tap marks present.
        case arrival
        /// Arrival has closed: the rest are absent, and a tap marks tardy.
        case late
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
    /// This device's phase for the day on screen. Local, not shared: another
    /// device sees the marks Late made, not the switch.
    private(set) var phase: Phase = .arrival
    /// The records the last switch to Late marked absent, for its Undo.
    @ObservationIgnored private var lastLateBatch: [NSManagedObjectID] = []

    /// The day on screen (start of day).
    private(set) var date: Date
    private let context: NSManagedObjectContext
    private let container: NSPersistentCloudKitContainer?
    private let store: CDAttendanceStore
    /// Records created since the last save, to put into the classroom share
    /// once that save gives them permanent IDs.
    private var createdSinceSave: [CDAttendanceRecord] = []
    /// Reloads the day when the guide's changes (or the whole class, on the
    /// first download) arrive from iCloud.
    @ObservationIgnored private var importReloader: RemoteImportReloader?

    init(context: NSManagedObjectContext, container: NSPersistentCloudKitContainer?, date: Date = Date()) {
        self.context = context
        self.container = container
        self.date = Calendar.current.startOfDay(for: date)
        // The role is hardcoded rather than read from the membership row: this
        // app is only ever used by an assistant, and ClassroomPermissions is
        // what stops a mis-set membership from writing beyond attendance.
        self.store = CDAttendanceStore(context: context, role: .assistant)
        self.importReloader = RemoteImportReloader { [weak self] in self?.load() }
    }

    /// Reloads the day whenever an import into the classroom's store finishes,
    /// until the calling task is cancelled.
    func followRemoteImports(into storeIdentifier: String) async {
        await importReloader?.observeImports(into: storeIdentifier)
    }

    /// Holds remote reloads while a sheet is editing one of the rows.
    func pauseRemoteReloads(_ paused: Bool) {
        importReloader?.isPaused = paused
    }

    /// Whether this day's marks can be changed: the role may write
    /// attendance, and the guide hasn't locked the day.
    var canMark: Bool {
        ClassroomPermissions.canWrite(entityName: "AttendanceRecord", role: .assistant) && !isLocked
    }

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// Shows `newDate` (any day, school or not), or reloads the current one.
    func load(_ newDate: Date? = nil) {
        if let newDate {
            let day = Calendar.current.startOfDay(for: newDate)
            if day != date { lastLateBatch = [] }
            date = day
        }
        phase = LatePhaseMemory.isLate(on: date) ? .late : .arrival
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

    /// What a tap on `row` does in the current phase. During Arrival a tap
    /// marks present and a second tap unmarks; during Late a tap turns absent
    /// (or unmarked) into tardy and a second tap turns it back. A present
    /// child is left alone during Late: the long-press menu changes that.
    static func statusAfterTap(from status: AttendanceStatus, in phase: Phase) -> AttendanceStatus? {
        switch (phase, status) {
        case (.arrival, .present): return .unmarked
        case (.arrival, _): return .present
        case (.late, .tardy): return .absent
        case (.late, .absent), (.late, .unmarked): return .tardy
        case (.late, _): return nil
        }
    }

    func tap(_ row: Row) {
        guard let next = Self.statusAfterTap(from: row.status, in: phase) else { return }
        setStatus(next, for: row)
    }

    /// Sets any status directly (the long-press menu), creating the record on
    /// the first mark.
    func setStatus(_ status: AttendanceStatus, for row: Row) {
        guard canMark else { return }
        do {
            guard let record = try store.ensureRecord(for: row.student, on: date) else { return }
            if record.isInserted { createdSinceSave.append(record) }
            _ = store.updateStatus(record, to: status)
            persist()
        } catch {
            Self.logger.error("Marking failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't save that mark."
        }
    }

    /// Closes arrival: every child still unmarked is marked absent. Returns
    /// how many it marked, for the Undo bar.
    @discardableResult
    func beginLate() -> Int {
        guard canMark, phase == .arrival else { return 0 }
        phase = .late
        LatePhaseMemory.setLate(true, on: date)
        do {
            let changed = try store.markUnmarkedAbsent(for: date, students: rows.map(\.student))
            createdSinceSave.append(contentsOf: changed.filter(\.isInserted))
            persist()
            lastLateBatch = changed.map(\.objectID)
            return changed.count
        } catch {
            Self.logger.error("Closing arrival failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't mark the rest absent."
            return 0
        }
    }

    /// Back to Arrival. Marks stay as they are unless `undo` is set, when the
    /// children the last switch to Late marked absent (and still are) go back
    /// to unmarked.
    func returnToArrival(undo: Bool = false) {
        phase = .arrival
        LatePhaseMemory.setLate(false, on: date)
        let batch = lastLateBatch
        lastLateBatch = []
        guard undo, canMark, !batch.isEmpty else { return }
        for id in batch {
            guard let record = try? context.existingObject(with: id) as? CDAttendanceRecord,
                  record.status == .absent else { continue }
            store.updateStatus(record, to: .unmarked)
        }
        persist()
    }

    func setAbsenceReason(_ reason: AbsenceReason, for row: Row) {
        guard canMark, let record = try? store.ensureRecord(for: row.student, on: date) else { return }
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

    /// Remembers, on this device, which day was switched to Late, so the phase
    /// survives a relaunch mid-morning. One day at a time: switching another
    /// day forgets the last.
    enum LatePhaseMemory {
        private static let key = "Assistant.latePhaseDay"

        static func isLate(on day: Date) -> Bool {
            guard let stored = UserDefaults.standard.object(forKey: key) as? Date else { return false }
            return Calendar.current.isDate(stored, inSameDayAs: day)
        }

        static func setLate(_ late: Bool, on day: Date) {
            if late {
                UserDefaults.standard.set(day, forKey: key)
            } else if isLate(on: day) {
                forget()
            }
        }

        static func forget() {
            UserDefaults.standard.removeObject(forKey: key)
        }
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
