// swiftlint:disable file_length
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
final class AssistantAttendanceViewModel { // swiftlint:disable:this type_body_length

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
    /// Bumped when she sets or removes a pickup time here (`setPickup`), for
    /// the pickup reminders (`EarlyPickupReminder`); other devices' arrive by
    /// import, which reloads.
    var pickupEdits = 0

    var unmarkedCount: Int { rows.count { $0.status == .unmarked } }
    /// How much of the class is in the room (late counts, left early
    /// doesn't), 0 to 1: the Cosmic background's stars.
    var hereFraction: Double {
        guard !rows.isEmpty else { return 0 }
        return Double(rows.count(where: \.isInRoom)) / Double(rows.count)
    }
    /// Bumped when her own mark (or closing arrival) leaves no one unmarked
    /// on a day that has arrived: the grid's ripple and the bar's "Everyone's
    /// here". Never by an import or a change of day.
    private(set) var completions = 0

    /// Whether `completions` going from `old` to `new` is a real finish. The
    /// screen reads it through an optional view model, so its first value
    /// arrives as nil to 0 when the model is made: that is a launch, not
    /// everyone being marked, and must not buzz or ring.
    nonisolated static func isCompletion(from old: Int?, to new: Int?) -> Bool {
        guard let old, let new else { return false }
        return new > old
    }

    /// A child just marked in after days away: "Welcome back, Maya" in the
    /// bar. Set only by her own marks, never an import or a change of day.
    private(set) var welcome: Welcome?

    /// The day on screen's school day of the year ("Day 37"), nil on a day
    /// off, before the first day, or before any mark this year has synced.
    private(set) var dayNumber: Int?
    var milestone: AttendanceSchoolDayCount.Milestone? { AttendanceSchoolDayCount.milestone(for: dayNumber) }
    @ObservationIgnored private var dayCounter = AttendanceDayCounter()

    /// The last failed save or bulk mark, else the last failed load. A save
    /// failure outlasts a successful reload (the change is still unsaved);
    /// a load failure clears on the next load that works.
    var errorMessage: String? { saveError ?? loadError }
    private var saveError: String?
    private var loadError: String?
    /// Set on weekends and on the guide's days off, which follow the notebook's
    /// school calendar (`SchoolDayChecker`): no marks are taken then.
    private(set) var dayOff: DayOff?
    /// The share's first day with attendance: the grid pages no earlier (`canStepBack`).
    private(set) var earliestDay: Date?
    /// Set when the guide has locked this day: its rows are read-only.
    private(set) var isLocked = false
    /// The phase for the day on screen: Late once arrival closed here, or on
    /// another device, which shows as Close Arrival's automatic absences
    /// (`AttendanceLatePhase`). Reopening it here holds on this phone.
    private(set) var phase: Phase = .arrival
    /// Bumped when her own Close Arrival, Reopen or Undo changes the phase,
    /// for the bar's tap of feedback. `phase` itself is worked out again by
    /// every load, so an import that closed arrival elsewhere buzzed too.
    private(set) var phaseSwitches = 0
    /// Close Arrival's automatic absence stands on a record of the day
    /// (closed here or on another device), so after Reopen Arrival the bar
    /// still offers the way back to Late with nobody left unmarked.
    private(set) var hasAutomaticAbsences = false
    /// Set by a tapped front-desk reminder with children still unmarked: the
    /// bar asks its Mark N Absent & Email question (`AssistantFrontDeskMail`),
    /// and clears it.
    var asksToCloseAndEmail = false
    /// The front-desk email for the day on screen.
    let frontDesk: AssistantFrontDesk
    /// The records the last Close Arrival marked absent, for its Undo.
    @ObservationIgnored private var lastLateBatch: [NSManagedObjectID] = []

    /// The day on screen (start of day).
    private(set) var date: Date
    let context: NSManagedObjectContext
    private let container: NSPersistentCloudKitContainer?
    private let store: CDAttendanceStore
    /// Every record the day holds, CloudKit duplicates included, by student
    /// id: a pickup can sit on a copy that lost to another's mark
    /// (`AttendanceRow.leavesAt`).
    @ObservationIgnored private var copiesByStudentID: [String: [CDAttendanceRecord]] = [:]
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
    /// until the calling task is cancelled. The screen's task calls this
    /// right after loading the day, so the screen is showing whatever scene
    /// change it last heard (a tab out of sight may not hear the return):
    /// nothing held from a trip away outlasts that load.
    func followRemoteImports(into storeIdentifier: String) async {
        importReloader?.appReturned()
        await importReloader?.observeImports(into: storeIdentifier)
    }

    /// The app left the screen (`isActive` false) or came back to it. Away,
    /// an import doesn't reload the day; back, the return-to-app reload
    /// (`AssistantReloadOnReturn`) shows it, and a reload held meanwhile is
    /// dropped rather than run as a second one.
    func followScene(isActive: Bool) {
        if isActive {
            importReloader?.appReturned()
        } else {
            importReloader?.appLeft()
        }
    }

    /// Holds remote reloads while a sheet is editing one of the rows.
    func pauseRemoteReloads(_ paused: Bool) {
        importReloader?.isPaused = paused
    }

    /// Whether this day's marks can be changed: the role may write
    /// attendance, and the guide hasn't locked the day. Worked out once per
    /// load; every tile reads it on every redraw.
    private(set) var canMark = false

    /// Everyone's names as the classroom's list has them, read once per load
    /// (an import reloads, so a rename on another device shows), for who
    /// made each mark and who sent the front-desk email.
    private(set) var names = ClassroomNames.Snapshot()

    private func refreshNames() {
        let current = ClassroomNames.snapshot(in: context)
        if current != names { names = current }
    }

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// A day after today: only absences (a known vacation, an appointment)
    /// and notes can be marked ahead.
    var isFuture: Bool { date > Calendar.current.startOfDay(for: Date()) }

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
        earliestDay = AssistantDayRoll.earliestRecordDay(in: context)
        dayOff = Self.dayOff(on: date, in: context)
        loadGeneration &+= 1
        isLocked = store.isLocked(date)
        canMark = store.canWrite(on: date)
        frontDesk.load(date)
        refreshNames()

        let fetched: [CDAttendanceRecord]
        do {
            fetched = try store.loadRecords(for: date)
            loadError = nil
        } catch {
            Self.logger.error("Loading attendance failed: \(error.localizedDescription, privacy: .public)")
            loadError = "Couldn't load the attendance for \(dayPhrase). Pull down to try again."
            fetched = []
        }
        // Closed here, or on another device: its automatic absences, as
        // `CDAttendanceStore.arrivalClosed` reads them.
        let closedAnywhere = fetched.contains(where: AttendanceDeduplication.isAutomaticAbsence)
        hasAutomaticAbsences = closedAnywhere
        phase = AttendanceLatePhase.isLate(on: date, closedAnywhere: closedAnywhere, defaults: defaults)
            ? .late : .arrival
        let records = fetched.deduplicatedPerStudentDay()
        copiesByStudentID = Dictionary(grouping: fetched, by: \.studentID)

        // The day's roll, not today's: a child who has since left still shows
        // on the days she was here, and anyone with a record that day shows
        // whatever their dates say (`AttendanceRoster`).
        let students = AssistantDayRoll.students(
            on: date, recordStudentIDs: Set(records.map(\.studentID)), in: context
        )
        // Siri marks today only, so its names follow today's roll.
        if isToday { AssistantSiriVocabulary.refresh(for: students) }

        let byStudent = Dictionary(records.map { ($0.studentID, $0) }, uniquingKeysWith: { first, _ in first })

        let gridNames = AttendanceGridNames.names(for: students)
        let returning = dayOff == nil ? AttendanceWelcomeBack.returning(on: date, in: context) : [:]
        rows = students.map { student in
            let key = student.id?.uuidString ?? ""
            return Row(
                student: student,
                record: byStudent[key],
                copies: copiesByStudentID[key] ?? [],
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
        guard !reloadIfGone(row) else { return }
        guard canMark, Self.allows(status, on: date) else { return }
        do {
            guard let record = try store.ensureRecord(for: row.student, on: date) else { return }
            if record.isInserted { createdSinceSave.append(record) }
            let wasHere = Self.isHere(record.status)
            // Clearing goes through every copy of the day, or a duplicate's
            // mark would win the child straight back (`CDAttendanceStore.unmark`).
            _ = status == .unmarked ? store.unmark(record) : store.updateStatus(record, to: status)
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
        // Locked since the day loaded: the store would mark no one, and
        // arrival used to close anyway. The reload shows the lock ("Your
        // guide has locked this day.") and takes the control away.
        guard store.canWrite(on: date) else {
            load()
            return 0
        }
        let changed: [CDAttendanceRecord]
        do {
            let students = rows.filter { !$0.studentIsGone }.map(\.student)
            changed = try store.markUnmarkedAbsent(for: date, students: students)
        } catch {
            // Nothing was marked, so arrival stays open (it used to go to
            // Late with the rest still unmarked).
            Self.logger.error("Closing arrival failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Couldn't mark the rest absent. Try again."
            return 0
        }
        phase = .late
        phaseSwitches += 1
        AttendanceLatePhase.setLate(true, on: date, defaults: defaults)
        // Siri's last change is from before arrival closed: "Undo that" now
        // would put back an older voice mark, not this.
        SiriAttendanceChange.forget(ifOn: date, defaults: defaults)
        createdSinceSave.append(contentsOf: changed.filter(\.isInserted))
        persist(updating: changed)
        lastLateBatch = changed.map(\.objectID)
        return changed.count
    }

    /// Back to Arrival. Reopen Arrival (no `undo`) is on purpose: marks stay
    /// as they are, and it holds on this phone even where another device's
    /// Close Arrival shows on the records (`AttendanceLatePhase.reopen`).
    /// Close Arrival's Undo (`undo`) puts the children it marked absent (and
    /// still are) back to unmarked, and the day follows the records again:
    /// a Close Arrival made on another device since still counts. Undo used
    /// to reopen on purpose, and the guide's later close was ignored here.
    func returnToArrival(undo: Bool = false) {
        // A day locked since arrival closed stays as it was: its absences
        // can't be put back, so reopening arrival would only mislead.
        guard canMark else { return }
        guard store.canWrite(on: date) else {
            load()
            return
        }
        let before = phase
        let batch = lastLateBatch
        lastLateBatch = []
        guard undo else {
            phase = .arrival
            if before != phase { phaseSwitches += 1 }
            AttendanceLatePhase.reopen(on: date, defaults: defaults)
            return
        }
        AttendanceLatePhase.setLate(false, on: date, defaults: defaults)
        var reverted: [CDAttendanceRecord] = []
        for id in batch {
            // Still Close Arrival's own absence: a child marked "Absent,
            // Sick" since keeps the reason, rather than going back to unmarked.
            guard let record = try? context.existingObject(with: id) as? CDAttendanceRecord,
                  store.undoAutomaticAbsence(record) else { continue }
            reverted.append(record)
        }
        persist(updating: reverted)
        // The copies the Undo cleared too, and the phase the records now give.
        load()
        if before != phase { phaseSwitches += 1 }
    }

    /// Absent with a reason (or none), in one save: the menu's Absent
    /// choices. Allowed on days ahead, for a known vacation or appointment.
    func markAbsent(reason: AbsenceReason, for row: Row) {
        guard !reloadIfGone(row) else { return }
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

    /// Writes `day`'s note for a student (the day on screen when nil),
    /// creating the record if there is none yet. Empty text removes the note.
    func setNote(_ text: String?, for row: Row, on day: Date? = nil) {
        editRecord(for: row, on: day, failure: "Couldn't save that note. Try again.") { store, record in
            store.updateNote(record, to: text)
        }
    }

    /// Writes one of a record's values that isn't its mark (the note, the
    /// pickup time), creating the record if there is none yet. `update`
    /// returns whether it changed anything; when it didn't, a record made
    /// just for it is dropped rather than left blank for the next save.
    /// Returns whether it saved.
    ///
    /// `day` is the day the sheet was opened on (the day on screen when
    /// nil): a reminder tapped or the morning coming round while it was
    /// open moves the grid on, and the note used to land on the new day.
    @discardableResult
    func editRecord(
        for row: Row,
        on day: Date? = nil,
        failure: String,
        _ update: (CDAttendanceStore, CDAttendanceRecord) -> Bool
    ) -> Bool {
        let day = day.map { Calendar.current.startOfDay(for: $0) } ?? date
        let isOnScreen = day == date
        guard !reloadIfGone(row), isOnScreen ? canMark : store.canWrite(on: day) else { return false }
        do {
            guard let record = try store.ensureRecord(for: row.student, on: day) else { return false }
            let isNew = record.isInserted
            guard update(store, record) else {
                if isNew { context.delete(record) }
                return false
            }
            if isNew { createdSinceSave.append(record) }
            // Another day's record is no row on screen.
            persist(updating: isOnScreen ? [record] : [])
            return saveError == nil
        } catch {
            Self.logger.error("Saving a record failed: \(error.localizedDescription, privacy: .public)")
            saveError = failure
            return false
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
        // A record made since the load joins the day's copies, so Close
        // Arrival's own absences count until the next load.
        for record in records where copiesByStudentID[record.studentID]?.contains(record) != true {
            copiesByStudentID[record.studentID, default: []].append(record)
        }
        hasAutomaticAbsences = copiesByStudentID.values.contains {
            $0.contains(where: AttendanceDeduplication.isAutomaticAbsence)
        }
        let wasOpen = unmarkedCount > 0
        updateRows(for: records)
        if wasOpen, unmarkedCount == 0, !rows.isEmpty, !isFuture { completions += 1 }
    }

    /// Rebuilds the rows whose student's record is among `records`.
    private func updateRows(for records: [CDAttendanceRecord]) {
        guard !records.isEmpty else { return }
        let byStudent = Dictionary(records.map { ($0.studentID, $0) }, uniquingKeysWith: { first, _ in first })
        rows = rows.map { row in
            guard !row.studentIsGone, let key = row.student.id?.uuidString, let record = byStudent[key] else {
                return row
            }
            return Row(
                student: row.student, record: record, copies: copiesByStudentID[key] ?? [],
                shortName: row.shortName, day: date, daysAway: row.daysAway
            )
        }
    }
}
