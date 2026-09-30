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

    private static let logger = Logger.app(category: "attendance")

    /// One child on the day, with their record's values copied in.
    typealias Row = AttendanceRow

    /// Which part of the morning the taps are for.
    typealias Phase = AttendancePhase

    /// Why there is no school on `date`, when there isn't.
    enum DayOff: Equatable {
        case weekend
        /// A day off in the guide's school calendar, with its reason if given.
        case holiday(String?)
    }

    private(set) var rows: [Row] = []
    /// Bumped by every full load (a day change, an import), for work that
    /// follows the roll as a whole: rescheduling the arrival reminder.
    private(set) var loadGeneration = 0

    var unmarkedCount: Int { rows.count { $0.status == .unmarked } }
    /// How much of the class is here (late and left early count), 0 to 1:
    /// the Cosmic background's stars.
    var hereFraction: Double {
        guard !rows.isEmpty else { return 0 }
        return Double(rows.count { Self.isHere($0.status) }) / Double(rows.count)
    }
    /// Bumped when her own mark (or closing arrival) leaves no one unmarked
    /// on a day that has arrived: the grid's ripple and the bar's "Everyone's
    /// here". Never by an import or a change of day.
    private(set) var completions = 0
    /// A child just marked in after days away: "Welcome back, Maya" in the
    /// bar. Set only by her own marks, never an import or a change of day.
    private(set) var welcome: Welcome?

    /// The day on screen's school day of the year ("Day 37"), nil on a day
    /// off, before the first day, or before any mark this year has synced.
    private(set) var dayNumber: Int?
    var milestone: AssistantSchoolDayCount.Milestone? { AssistantSchoolDayCount.milestone(for: dayNumber) }
    @ObservationIgnored private var dayCounter = AssistantDayCounter()

    /// The last failed save or bulk mark, else the last failed load. A save
    /// failure outlasts a successful reload (the change is still unsaved);
    /// a load failure clears on the next load that works.
    var errorMessage: String? { saveError ?? loadError }
    private var saveError: String?
    private var loadError: String?
    /// Set on weekends and on the guide's days off, which follow the notebook's
    /// school calendar (`SchoolDayChecker`): no marks are taken then.
    private(set) var dayOff: DayOff?
    /// Set when the guide has locked this day: its rows are read-only.
    private(set) var isLocked = false
    /// This device's phase for the day on screen. Local, not shared: another
    /// device sees the marks Late made, not the switch.
    private(set) var phase: Phase = .arrival
    /// The front-desk email for the day on screen.
    let frontDesk: AssistantFrontDesk
    /// The records the last Close Arrival marked absent, for its Undo.
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

    /// Where the Late phase is remembered; tests pass their own suite.
    private let defaults: UserDefaults

    init(
        context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?,
        date: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        self.context = context
        self.container = container
        self.defaults = defaults
        self.date = Calendar.current.startOfDay(for: date)
        // The role is hardcoded rather than read from the membership row: this
        // app is only ever used by an assistant, and ClassroomPermissions is
        // what stops a mis-set membership from writing beyond attendance.
        self.store = CDAttendanceStore(context: context, role: .assistant)
        self.frontDesk = AssistantFrontDesk(context: context, container: container)
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
    /// attendance, and the guide hasn't locked the day. Worked out once per
    /// load; every tile reads it on every redraw.
    private(set) var canMark = false

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// A day after today: only absences (a known vacation, an appointment)
    /// and notes can be marked ahead.
    var isFuture: Bool { date > Calendar.current.startOfDay(for: Date()) }

    /// The children still unmarked, by the names on their tiles: Close
    /// Arrival's list.
    var unmarkedNames: [String] {
        rows.filter { $0.status == .unmarked }.map(\.shortName)
    }

    /// Whether the bar offers Close Arrival (someone still unmarked) or shows
    /// Late. Never on a locked day or a day ahead.
    var showsArrivalControl: Bool {
        guard canMark, !isFuture else { return false }
        switch phase {
        case .arrival: return !unmarkedNames.isEmpty
        case .late: return true
        }
    }

    /// The statuses the long-press menu offers on the day on screen.
    var menuStatuses: [AttendanceStatus] {
        [.present, .absent, .tardy, .leftEarly, .unmarked].filter { Self.allows($0, on: date) }
    }

    /// What a tap on `row` does today, or nil when it does nothing: a present
    /// child during Late, and every tap on a day ahead.
    func statusAfterTap(for row: Row) -> AttendanceStatus? {
        guard !isFuture else { return nil }
        return Self.statusAfterTap(from: row.status, in: phase)
    }

    /// A readable name for the day on screen, for messages.
    private var dayPhrase: String {
        isToday ? "today" : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
    /// Shows `newDate` (any day, school or not), or reloads the current one.
    func load(_ newDate: Date? = nil) {
        if let newDate {
            let day = Calendar.current.startOfDay(for: newDate)
            if day != date { lastLateBatch = [] }
            date = day
        }
        phase = AttendanceLatePhase.isLate(on: date, defaults: defaults) ? .late : .arrival
        dayOff = Self.dayOff(on: date, in: context)
        loadGeneration &+= 1
        isLocked = store.isLocked(date)
        canMark = store.canWrite(on: date)
        frontDesk.load(date)

        let records: [CDAttendanceRecord]
        do {
            records = try store.loadRecords(for: date).deduplicatedPerStudentDay()
            loadError = nil
        } catch {
            Self.logger.error("Loading attendance failed: \(error.localizedDescription, privacy: .public)")
            loadError = "Couldn't load the attendance for \(dayPhrase). Pull down to try again."
            records = []
        }

        // The day's roll, not today's: a child who has since left still shows
        // on the days she was here, and anyone with a record that day shows
        // whatever their dates say (`AttendanceRoster`).
        let students = AssistantDayRoll.students(
            on: date, recordStudentIDs: Set(records.map(\.studentID)), in: context
        )
        // Siri marks today only, so its names follow today's roll.
        if isToday { AssistantSiriVocabulary.refresh(for: students) }

        let byStudent = Dictionary(
            records.map { ($0.studentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let gridNames = AttendanceGridNames.names(for: students)
        let returning = dayOff == nil ? AssistantWelcomeBack.returning(on: date, in: context) : [:]
        rows = students.map { student in
            let key = student.id?.uuidString ?? ""
            return Row(
                student: student,
                record: byStudent[key],
                shortName: gridNames[student.objectID] ?? student.shortName,
                day: date,
                daysAway: returning[key]
            )
        }
        if case .counted(let number) = dayCounter.count(
            date, isDayOff: dayOff != nil, current: dayNumber, in: context
        ) {
            dayNumber = number
        }
    }

    func tap(_ row: Row) {
        guard let next = statusAfterTap(for: row) else { return }
        setStatus(next, for: row)
    }

    /// Sets any status directly (the long-press menu), creating the record on
    /// the first mark.
    func setStatus(_ status: AttendanceStatus, for row: Row) {
        guard canMark, Self.allows(status, on: date) else { return }
        do {
            guard let record = try store.ensureRecord(for: row.student, on: date) else { return }
            if record.isInserted { createdSinceSave.append(record) }
            let wasHere = Self.isHere(record.status)
            _ = store.updateStatus(record, to: status)
            persist(updating: [record])
            if row.daysAway != nil, !wasHere, Self.isHere(status), saveError == nil {
                welcome = Welcome(name: row.shortName)
            }
        } catch {
            Self.logger.error("Marking failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Couldn't save that mark. Try again."
        }
    }

    /// Closes arrival: every child still unmarked is marked absent. Returns
    /// how many it marked, for the Undo bar.
    @discardableResult
    func beginLate() -> Int {
        guard canMark, !isFuture, phase == .arrival else { return 0 }
        phase = .late
        AttendanceLatePhase.setLate(true, on: date, defaults: defaults)
        do {
            let changed = try store.markUnmarkedAbsent(for: date, students: rows.map(\.student))
            createdSinceSave.append(contentsOf: changed.filter(\.isInserted))
            persist(updating: changed)
            lastLateBatch = changed.map(\.objectID)
            return changed.count
        } catch {
            Self.logger.error("Closing arrival failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Couldn't mark the rest absent. Try again."
            return 0
        }
    }

    /// Back to Arrival. Marks stay as they are unless `undo` is set, when the
    /// children the last Close Arrival marked absent (and still are) go back
    /// to unmarked.
    func returnToArrival(undo: Bool = false) {
        // A day locked since arrival closed stays as it was: its absences
        // can't be put back, so reopening arrival would only mislead.
        guard canMark else { return }
        phase = .arrival
        AttendanceLatePhase.setLate(false, on: date, defaults: defaults)
        let batch = lastLateBatch
        lastLateBatch = []
        guard undo, !batch.isEmpty else { return }
        var reverted: [CDAttendanceRecord] = []
        for id in batch {
            guard let record = try? context.existingObject(with: id) as? CDAttendanceRecord,
                  record.status == .absent else { continue }
            store.updateStatus(record, to: .unmarked)
            reverted.append(record)
        }
        persist(updating: reverted)
    }

    /// Absent with a reason (or none), in one save: the menu's Absent
    /// choices. Allowed on days ahead, for a known vacation or appointment.
    func markAbsent(reason: AbsenceReason, for row: Row) {
        guard canMark, Self.allows(.absent, on: date) else { return }
        do {
            guard let record = try store.ensureRecord(for: row.student, on: date) else { return }
            if record.isInserted { createdSinceSave.append(record) }
            store.updateStatus(record, to: .absent)
            store.updateAbsenceReason(record, to: reason)
            persist(updating: [record])
        } catch {
            Self.logger.error("Marking absent failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Couldn't save that mark. Try again."
        }
    }

    /// Writes the day's note for a student, creating the record if there is
    /// none yet. Empty text removes the note.
    func setNote(_ text: String?, for row: Row) {
        guard canMark else { return }
        do {
            guard let record = try store.ensureRecord(for: row.student, on: date) else { return }
            let isNew = record.isInserted
            guard store.updateNote(record, to: text) else {
                // Saving an empty note on an unmarked child isn't a mark:
                // leave no blank record waiting for the next save.
                if isNew { context.delete(record) }
                return
            }
            if isNew { createdSinceSave.append(record) }
            persist(updating: [record])
        } catch {
            Self.logger.error("Saving a note failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Couldn't save that note. Try again."
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

    /// Saves, puts new records into the classroom share, and redraws the
    /// rows for `records`. Only those rows: the rest of the day hasn't
    /// changed, and a full `load()` (every student, every record, the
    /// calendar and the lock) after each tap was most of a tap's cost.
    private func persist(updating records: [CDAttendanceRecord]) {
        // A failed save here is this phone's own store refusing the change,
        // not the network: iCloud sending is the sync line's business, and it
        // retries by itself. The change stays pending, so the next mark's
        // save tries it again.
        guard AssistantSave.save(context, container: container, created: createdSinceSave) else {
            saveError = "Couldn't save that change. Try again."
            return
        }
        saveError = nil
        createdSinceSave = []
        let wasOpen = unmarkedCount > 0
        updateRows(for: records)
        if wasOpen, unmarkedCount == 0, !rows.isEmpty, !isFuture { completions += 1 }
    }

    /// Rebuilds the rows whose student's record is among `records`.
    private func updateRows(for records: [CDAttendanceRecord]) {
        guard !records.isEmpty else { return }
        let byStudent = Dictionary(records.map { ($0.studentID, $0) }, uniquingKeysWith: { first, _ in first })
        rows = rows.map { row in
            guard let key = row.student.id?.uuidString, let record = byStudent[key] else { return row }
            return Row(
                student: row.student, record: record, shortName: row.shortName, day: date, daysAway: row.daysAway
            )
        }
    }
}
