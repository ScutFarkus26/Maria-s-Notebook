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
    /// The records behind the rows, by student id, for writing (the undo
    /// extension reads it too).
    @ObservationIgnored private(set) var recordsByStudentID: [String: CDAttendanceRecord] = [:]

    /// This device's phase for the day on screen (`AttendanceLatePhase`):
    /// after Close Arrival a tap on an iPhone tile marks late, and Siri's
    /// "here" does too.
    private(set) var phase: AttendancePhase = .arrival
    /// Bumped when a mark made here leaves no one unmarked on a day that has
    /// arrived: the success tap and "Everyone's here". Never by a load.
    private(set) var completions = 0

    /// A child marked in after days away, for "Welcome back, Maya".
    struct Welcome: Equatable {
        let id = UUID()
        let name: String
    }

    /// Set when a mark made here brings in a child back after days away
    /// (`AttendanceWelcomeBack`); never by a load or an import.
    private(set) var welcome: Welcome?

    /// The day on screen's school day of the year ("Day 37"), nil on a day
    /// off, before the year's first day, or before anyone was marked here.
    private(set) var dayNumber: Int?
    /// Counts school days from the year's first here-mark, as the Daybook
    /// Assistant does, so both show the same number.
    @ObservationIgnored private var dayCounter = AttendanceDayCounter()

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

    /// Changes the sort and writes it back, so reopening attendance lands on the same order.
    func setSortKey(_ newValue: SortKey) {
        guard newValue != sortKey else { return }
        sortKey = newValue
        SyncedPreferencesStore.shared.set(newValue.rawValue, forKey: Self.sortKeyPreferenceKey)
        students = sortedAndFiltered(students: students)
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rows = students.compactMap { $0.id.flatMap { byID[$0] } }
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
        let isDayOff = SchoolDayChecker.isNonSchoolDay(target, using: modelContext)
        if case .counted(let number) = dayCounter.count(
            target, isDayOff: isDayOff, current: dayNumber, in: modelContext
        ) {
            dayNumber = number
        }
        let returning = isDayOff ? [:] : AttendanceWelcomeBack.returning(on: target, in: modelContext)
        let gridNames = AttendanceGridNames.names(for: students)
        rows = students.map { student in
            AttendanceRow(
                student: student,
                record: recordsByStudentID[student.cloudKitKey],
                shortName: gridNames[student.objectID] ?? student.shortName,
                day: target,
                daysAway: returning[student.cloudKitKey]
            )
        }
    }

    // MARK: - Marking

    /// A tile's tap or a card's click (`statusAfterTap`): present during
    /// arrival, late after it closes, as on the Daybook Assistant.
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
        welcomeBack(row, to: status)
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

    /// Back in Class: a child who left early has come back, to present or
    /// late as they were, with the trip out on the record
    /// (`CDAttendanceStore.markBack`).
    func markBack(_ row: AttendanceRow, modelContext: NSManagedObjectContext) {
        guard AttendanceRules.allowsBack(for: row),
              let record = record(for: row, modelContext: modelContext),
              CDAttendanceStore(context: modelContext).markBack(record) else { return }
        changed([record])
    }

    /// "Welcome back" when a child back after days away is marked in.
    private func welcomeBack(_ row: AttendanceRow, to status: AttendanceStatus) {
        let comesIn = status == .present || status == .tardy || status == .leftEarly
        guard row.daysAway != nil, !row.isHere, comesIn else { return }
        welcome = Welcome(name: row.shortName)
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

    /// Sets when the child is due to be picked up early, or with nil removes
    /// it, creating the record if there is none yet. Marks nothing, and
    /// leaves no blank record behind.
    func updatePickup(for row: AttendanceRow, time: Date?, modelContext: NSManagedObjectContext) {
        guard let record = record(for: row, modelContext: modelContext) else { return }
        let isNew = record.isInserted
        guard CDAttendanceStore(context: modelContext).updateLeavesAt(record, to: time) else {
            if isNew { forget(record, in: modelContext) }
            return
        }
        changed([record])
    }

    // MARK: - Closing arrival

    /// Closes arrival on this device: every child still unmarked is marked
    /// absent, and from then on a tile's tap (and Siri's "here") marks late.
    /// Returns what the Undo needs, or nil when it couldn't close.
    func closeArrival(modelContext: NSManagedObjectContext) -> BulkMark? {
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
            // As on the Assistant's grid: Siri's last change is from before
            // arrival closed, so "Undo that" can't reach past this.
            SiriAttendanceChange.forget(ifOn: selectedDate, defaults: defaults)
            changed(marked)
            return BulkMark(day: selectedDate, records: marked.map(\.objectID), status: .absent)
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
    func undoCloseArrival(_ undo: BulkMark, modelContext: NSManagedObjectContext) -> Int {
        AttendanceLatePhase.setLate(false, on: undo.day, defaults: defaults)
        if undo.day == selectedDate { phase = .arrival }
        return undoBulkMark(undo, modelContext: modelContext)
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
    func changed(_ records: [CDAttendanceRecord]) {
        let wasOpen = unmarkedCount > 0
        updateRows(for: records)
        if wasOpen, unmarkedCount == 0, !rows.isEmpty, !isFuture { completions += 1 }
    }

    /// Rebuilds the rows whose student's record is among `records`.
    func updateRows(for records: [CDAttendanceRecord]) {
        guard !records.isEmpty else { return }
        let byStudent = Dictionary(records.map { ($0.studentID, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, record) in byStudent { recordsByStudentID[key] = record }
        rows = rows.map { row in
            guard let record = byStudent[row.student.cloudKitKey] else { return row }
            return AttendanceRow(
                student: row.student, record: record, shortName: row.shortName,
                day: selectedDate, daysAway: row.daysAway
            )
        }
    }
}
