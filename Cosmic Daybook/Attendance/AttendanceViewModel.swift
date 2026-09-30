import Foundation
import SwiftUI
import CoreData
import OSLog

/// One day's roll in the notebook: the children on it, in the chosen order,
/// each with the record that day holds for them (`AttendanceRow`), and every
/// change the roll offers. Rows are values, copied in on each load and after
/// each change, so a card redraws exactly when what it shows changed.
///
/// Rows are *virtual* until marked: a child with no record shows as
/// unmarked, and the first mark creates the record (`CDAttendanceStore`).
/// Callers save after each change.
@Observable
final class AttendanceViewModel {
    private static let logger = Logger.attendance
    private(set) var selectedDate: Date
    /// The day's roll, sorted: enrolled that day by their dates, or holding a
    /// record that day (`AttendanceRoster`).
    private(set) var students: [CDStudent] = []
    private(set) var rows: [AttendanceRow] = []
    /// The records behind the rows, by student id, for writing.
    @ObservationIgnored private var recordsByStudentID: [String: CDAttendanceRecord] = [:]

    /// This device's phase for the day on screen (`AttendanceLatePhase`):
    /// after Close Arrival a tap on an iPhone tile marks late, and Siri's
    /// "here" does too.
    private(set) var phase: AttendancePhase = .arrival
    /// Bumped when a mark made here leaves no one unmarked on a day that has
    /// arrived: the success tap and "Everyone's here". Never by a load.
    private(set) var completions = 0

    enum SortKey: String, CaseIterable { case firstName, lastName }

    /// The picker's last choice, remembered across launches (and across devices, since the key syncs).
    static let sortKeyPreferenceKey = "Attendance.sortKey"

    private(set) var sortKey: SortKey = AttendanceViewModel.storedSortKey()

    /// Where the Late phase is remembered; tests pass their own suite.
    @ObservationIgnored private let defaults: UserDefaults

    init(selectedDate: Date = Date(), defaults: UserDefaults = .standard) {
        self.selectedDate = selectedDate.normalizedDay()
        self.defaults = defaults
    }

    /// Reads the stored sort choice, falling back to last name for a notebook that has never set one.
    static func storedSortKey() -> SortKey {
        let raw = SyncedPreferencesStore.shared.string(forKey: sortKeyPreferenceKey)
        return raw.flatMap(SortKey.init(rawValue:)) ?? .lastName
    }

    /// Changes the sort and writes it back, so reopening attendance lands on the same order.
    func setSortKey(_ newValue: SortKey) {
        guard newValue != sortKey else { return }
        sortKey = newValue
        SyncedPreferencesStore.shared.set(newValue.rawValue, forKey: Self.sortKeyPreferenceKey)
        students = sortedAndFiltered(students: students)
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rows = students.compactMap { $0.id.flatMap { byID[$0] } }
    }

    // MARK: - The day

    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    /// A day after today: only absences and notes can be marked ahead.
    var isFuture: Bool { selectedDate > Calendar.current.startOfDay(for: Date()) }

    /// The statuses the menu offers on the day on screen.
    var menuStatuses: [AttendanceStatus] { AttendanceRules.menuStatuses(on: selectedDate) }

    var unmarkedCount: Int { rows.count { $0.status == .unmarked } }

    /// The children still unmarked, by full name: Close Arrival's list.
    var unmarkedNames: [String] {
        rows.filter { $0.status == .unmarked }.map(\.name)
    }

    /// Whether Close Arrival is on offer: someone's still unmarked, arrival
    /// is open, and the day has arrived. `canMark` is the caller's (a locked
    /// day can't be).
    func offersCloseArrival(canMark: Bool) -> Bool {
        canMark && !isFuture && phase == .arrival && unmarkedCount > 0
    }

    /// What a tap on an iPhone tile does, or nil when it does nothing: a
    /// present child during Late, and every tap on a day ahead.
    func statusAfterTap(for row: AttendanceRow) -> AttendanceStatus? {
        guard !isFuture else { return nil }
        return AttendanceRules.statusAfterTap(from: row.status, in: phase)
    }

    // MARK: - Filtering

    func visibleStudents(from all: [CDStudent]) -> [CDStudent] {
        TestStudentsFilter.filterVisible(all)
    }

    func sortedAndFiltered(students: [CDStudent]) -> [CDStudent] {
        switch sortKey {
        case .firstName:
            return students.sorted(by: StudentSortComparator.byFirstName)
        case .lastName:
            return students.sorted(by: StudentSortComparator.byLastName)
        }
    }

    // MARK: - Loading

    /// Loads `date`'s roll from `students`, every candidate (not just the
    /// day's roll: the roll depends on which records the day holds, and
    /// those come from this load).
    func load(for date: Date? = nil, students candidates: [CDStudent], modelContext: NSManagedObjectContext) {
        let target = (date ?? selectedDate).normalizedDay()
        selectedDate = target
        phase = AttendanceLatePhase.isLate(on: target, defaults: defaults) ? .late : .arrival
        let store = CDAttendanceStore(context: modelContext)
        let records: [CDAttendanceRecord]
        do {
            // Existing records only: the first mark creates one (`ensureRecord`).
            records = try store.loadRecords(for: target).deduplicatedPerStudentDay()
        } catch {
            Self.logger.warning("Failed to load records: \(error)")
            return
        }
        let roll = AttendanceRoster.students(
            on: target, from: candidates, recordStudentIDs: Set(records.map(\.studentID))
        )
        students = sortedAndFiltered(students: roll)
        let allowed = Set(students.compactMap { $0.id?.uuidString })
        recordsByStudentID = Dictionary(
            records.filter { allowed.contains($0.studentID) }.map { ($0.studentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let gridNames = AttendanceGridNames.names(for: students)
        rows = students.map { student in
            AttendanceRow(
                student: student,
                record: recordsByStudentID[student.cloudKitKey],
                shortName: gridNames[student.objectID] ?? student.shortName,
                day: target
            )
        }
    }

    // MARK: - Marking

    /// The Mac's (and iPad's) click: the next status in the cycle this day
    /// allows.
    func cycleStatus(for row: AttendanceRow, modelContext: NSManagedObjectContext) {
        let next = AttendanceRules.cycle(from: row.status, on: selectedDate)
        if setStatus(next, for: row, modelContext: modelContext) {
            HapticService.shared.selection()
        }
    }

    /// An iPhone tile's tap (`statusAfterTap`). The tile plays its own tick.
    func tap(_ row: AttendanceRow, modelContext: NSManagedObjectContext) {
        guard let next = statusAfterTap(for: row) else { return }
        setStatus(next, for: row, modelContext: modelContext)
    }

    /// Sets any status the day allows, creating the record on the first
    /// mark. Returns whether anything changed.
    @discardableResult
    func setStatus(_ status: AttendanceStatus, for row: AttendanceRow, modelContext: NSManagedObjectContext) -> Bool {
        guard AttendanceRules.allows(status, on: selectedDate),
              let record = record(for: row, modelContext: modelContext) else { return false }
        let store = CDAttendanceStore(context: modelContext)
        guard store.updateStatus(record, to: status) else { return false }
        changed([record])
        return true
    }

    /// Absent with a reason (or none), in one step: the menu's Absent
    /// choices. Allowed on days ahead, for a known vacation or appointment.
    func markAbsent(reason: AbsenceReason, for row: AttendanceRow, modelContext: NSManagedObjectContext) {
        guard let record = record(for: row, modelContext: modelContext) else { return }
        let store = CDAttendanceStore(context: modelContext)
        let marked = store.updateStatus(record, to: .absent)
        let reasoned = store.updateAbsenceReason(record, to: reason)
        if marked || reasoned { changed([record]) }
    }

    /// Writes the day's note, creating the record if there is none yet.
    /// Empty text removes the note, and leaves no blank record behind.
    func updateNote(for row: AttendanceRow, note: String?, modelContext: NSManagedObjectContext) {
        guard let record = record(for: row, modelContext: modelContext) else { return }
        let isNew = record.isInserted
        guard CDAttendanceStore(context: modelContext).updateNote(record, to: note) else {
            if isNew { forget(record, in: modelContext) }
            return
        }
        changed([record])
    }

    /// Marks the whole roll present. Not ahead of the day.
    func markAllPresent(modelContext: NSManagedObjectContext) {
        guard !isFuture else { return }
        do {
            let store = CDAttendanceStore(context: modelContext)
            changed(try store.markAllPresent(for: selectedDate, students: students))
        } catch {
            Self.logger.warning("Failed to mark all present: \(error)")
        }
    }

    // MARK: - Closing arrival

    /// What a Close Arrival marked absent, for its Undo.
    struct ArrivalUndo {
        let day: Date
        let records: [NSManagedObjectID]
    }

    /// Closes arrival on this device: every child still unmarked is marked
    /// absent, and from then on a tile's tap (and Siri's "here") marks late.
    /// Returns what the Undo needs, or nil when it couldn't close.
    func closeArrival(modelContext: NSManagedObjectContext) -> ArrivalUndo? {
        guard !isFuture, phase == .arrival else { return nil }
        let store = CDAttendanceStore(context: modelContext)
        guard store.canWrite(on: selectedDate) else { return nil }
        do {
            let marked = try store.markUnmarkedAbsent(for: selectedDate, students: students)
            // A record created here has a temporary id until the save that
            // follows; the Undo needs the one that lasts.
            try modelContext.obtainPermanentIDs(for: marked.filter(\.objectID.isTemporaryID))
            phase = .late
            AttendanceLatePhase.setLate(true, on: selectedDate, defaults: defaults)
            changed(marked)
            return ArrivalUndo(day: selectedDate, records: marked.map(\.objectID))
        } catch {
            Self.logger.warning("Failed to close arrival: \(error)")
            return nil
        }
    }

    /// Mark Rest Absent & Email: everyone still unmarked goes absent before
    /// the front-desk email. That's Close Arrival, or, with arrival already
    /// closed here, just the children still unmarked.
    func markUnmarkedAbsent(modelContext: NSManagedObjectContext) {
        guard closeArrival(modelContext: modelContext) == nil, !isFuture else { return }
        do {
            let store = CDAttendanceStore(context: modelContext)
            changed(try store.markUnmarkedAbsent(for: selectedDate, students: students))
        } catch {
            Self.logger.warning("Failed to mark the rest absent: \(error)")
        }
    }

    /// Back to Arrival on the day on screen; marks stay as they are.
    func reopenArrival() {
        phase = .arrival
        AttendanceLatePhase.setLate(false, on: selectedDate, defaults: defaults)
    }

    /// Undoes a Close Arrival: its day reopens, and the children it marked
    /// absent (and still are) go back to unmarked. Returns how many.
    @discardableResult
    func undoCloseArrival(_ undo: ArrivalUndo, modelContext: NSManagedObjectContext) -> Int {
        AttendanceLatePhase.setLate(false, on: undo.day, defaults: defaults)
        let store = CDAttendanceStore(context: modelContext)
        var reverted: [CDAttendanceRecord] = []
        for id in undo.records {
            guard let record = try? modelContext.existingObject(with: id) as? CDAttendanceRecord,
                  record.status == .absent,
                  store.updateStatus(record, to: .unmarked) else { continue }
            reverted.append(record)
        }
        if undo.day == selectedDate {
            phase = .arrival
            updateRows(for: reverted)
        }
        return reverted.count
    }

    // MARK: - Reset

    /// What a Reset Day cleared, for its Undo.
    struct ResetUndo {
        let day: Date
        let snapshots: [AttendanceRecordSnapshot]
        let wasLate: Bool
    }

    /// Clears the day's marks, reasons and notes, and reopens arrival.
    /// Returns what the Undo needs, or nil when nothing changed.
    func resetDay(modelContext: NSManagedObjectContext) -> ResetUndo? {
        let store = CDAttendanceStore(context: modelContext)
        do {
            let snapshots = try store.resetDay(for: selectedDate, students: students)
            let wasLate = phase == .late
            if wasLate { reopenArrival() }
            changed(snapshots.compactMap { try? modelContext.existingObject(with: $0.objectID) as? CDAttendanceRecord })
            guard !snapshots.isEmpty else { return nil }
            return ResetUndo(day: selectedDate, snapshots: snapshots, wasLate: wasLate)
        } catch {
            Self.logger.warning("Failed to reset day: \(error)")
            return nil
        }
    }

    /// Puts back what `undo`'s reset cleared, child by child, unless a child
    /// has been marked again since. Returns how many came back.
    @discardableResult
    func undoReset(_ undo: ResetUndo, modelContext: NSManagedObjectContext) -> Int {
        let restored = CDAttendanceStore(context: modelContext).restore(undo.snapshots)
        if undo.wasLate {
            AttendanceLatePhase.setLate(true, on: undo.day, defaults: defaults)
            if undo.day == selectedDate { phase = .late }
        }
        if undo.day == selectedDate { updateRows(for: restored) }
        return restored.count
    }

    // MARK: - Stats

    var countPresent: Int { rows.count { $0.status == .present } }
    var countAbsent: Int { rows.count { $0.status == .absent } }
    var countTardy: Int { rows.count { $0.status == .tardy } }
    var countLeftEarly: Int { rows.count { $0.status == .leftEarly } }

    /// "In Class" counts students who are either Present or Tardy.
    /// This is a derived metric for the header summary only and does not change stored data.
    var inClassCount: Int { countPresent + countTardy }

    // MARK: - Rows

    /// The row's record, created on the first mark. Nil when the child has
    /// no id or the day can't be written.
    private func record(for row: AttendanceRow, modelContext: NSManagedObjectContext) -> CDAttendanceRecord? {
        if let existing = recordsByStudentID[row.student.cloudKitKey] { return existing }
        do {
            return try CDAttendanceStore(context: modelContext).ensureRecord(for: row.student, on: selectedDate)
        } catch {
            Self.logger.warning("Failed to create a record: \(error)")
            return nil
        }
    }

    private func forget(_ record: CDAttendanceRecord, in context: NSManagedObjectContext) {
        recordsByStudentID[record.studentID] = nil
        context.delete(record)
    }

    /// Redraws the rows for `records` and notes when a mark made here
    /// completes the roll.
    private func changed(_ records: [CDAttendanceRecord]) {
        let wasOpen = unmarkedCount > 0
        updateRows(for: records)
        if wasOpen, unmarkedCount == 0, !rows.isEmpty, !isFuture { completions += 1 }
    }

    /// Rebuilds the rows whose student's record is among `records`.
    private func updateRows(for records: [CDAttendanceRecord]) {
        guard !records.isEmpty else { return }
        let byStudent = Dictionary(records.map { ($0.studentID, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, record) in byStudent { recordsByStudentID[key] = record }
        rows = rows.map { row in
            guard let record = byStudent[row.student.cloudKitKey] else { return row }
            return AttendanceRow(student: row.student, record: record, shortName: row.shortName, day: selectedDate)
        }
    }
}
