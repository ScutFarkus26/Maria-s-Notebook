//
//  StudentDeparture.swift
//  Cosmic Daybook
//
//  What leaving the class does, in one place (domain logic review
//  2026-11-20, R7). `StudentRepository.updateStudent` runs it whenever a
//  child's status becomes withdrawn or transferred: the student page offers
//  it (Remove or Keep), and Claude's `update_student` always does it.
//
//  Her last day (`dateWithdrawn`) is inclusive, so the cascade touches only
//  what lies after it:
//  - lessons planned but not given, and year-plan entries still pencilled in
//    (`StudentDeparturePlans`): those dated after her last day, and, once
//    her last day has passed, the undated and overdue ones too;
//  - the co-teacher groups she is in, from the day after her last day
//    (`TimetableService.takeOutOfGroups`);
//  - her open work that is hers alone, closed as Incomplete through
//    `WorkLogService`, once her last day has passed. Work shared with
//    classmates stays open for them.
//  Recorded on Monday that Maya leaves Friday, she keeps this week's lessons,
//  groups and work, and is in class on every screen through Friday.
//
//  A departure recorded ahead of (or on) her last day leaves the rest owed:
//  the undated and overdue plans and entries and her open work wait for the
//  day after it. The ledger marks her (`DepartureSkipLedger.setOwed`), unless
//  the guide chose Keep Plans, and the first launch after her last day
//  finishes the cascade (`finishOwedAndSave`). Without that, nothing ran
//  again once the day had passed: saving her again changes neither field.
//
//  Re-enrolling her un-skips the year-plan entries her departure skipped,
//  and only those (`returning`). A hand skip looks the same on the entry, so
//  the departure keeps the ids it skipped in a list of its own
//  (`DepartureSkipLedger`), synced through iCloud key-value storage; no
//  field on the entry changes meaning. A departure recorded before this
//  build, or a list lost with a restore, un-skips nothing.
//

import CoreData
import Foundation

enum StudentDeparture {

    /// What the cascade would take her off, for the student page's question.
    struct Pending {
        var plans: [CDLessonAssignment] = []
        var entries: [CDYearPlanEntry] = []
        var openWork: [CDWorkModel] = []
        var isInGroups = false

        var isEmpty: Bool { plans.isEmpty && entries.isEmpty && openWork.isEmpty && !isInGroups }
    }

    /// What the cascade did.
    struct Report: Equatable {
        var plans = StudentDeparturePlans.Retraction()
        var entriesSkipped = 0
        var workClosed = 0
        var groupsChanged = 0
    }

    /// The first day she is no longer in class: the day after her last day,
    /// or today when she has none.
    static func firstDayGone(lastDay: Date?, now: Date = Date(), calendar: Calendar = AppCalendar.shared) -> Date {
        guard let lastDay else { return calendar.startOfDay(for: now) }
        let start = calendar.startOfDay(for: lastDay)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }

    /// Whether her last day has passed (a departure with no last day counts
    /// from today): the whole cascade can run.
    static func hasGone(lastDay: Date?, now: Date = Date(), calendar: Calendar = AppCalendar.shared) -> Bool {
        firstDayGone(lastDay: lastDay, now: now, calendar: calendar) <= calendar.startOfDay(for: now)
    }

    // MARK: - What it would do

    /// What the cascade takes her off now. With `eventually`, also what it
    /// takes off once her last day has passed (the undated and overdue
    /// plans and entries, her open work), though not this week's lessons
    /// before her last day, which she is expected to have: what the student
    /// page asks about, so Keep Plans is offered for what Remove will take.
    static func pending(
        studentID: UUID, lastDay: Date?, in context: NSManagedObjectContext,
        now: Date = Date(), calendar: Calendar = AppCalendar.shared, eventually: Bool = false
    ) -> Pending {
        let gone = firstDayGone(lastDay: lastDay, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let hasGone = gone <= today
        // A plan or entry comes off now when it falls after her last day, or
        // every one once she has gone; `eventually` adds the undated and overdue.
        let comesOff: (Date?) -> Bool = { date in
            if hasGone { return true }
            guard let date else { return eventually }
            return date >= gone || (eventually && date < today)
        }
        return Pending(
            plans: StudentDeparturePlans.futurePlans(for: studentID, in: context)
                .filter { comesOff($0.scheduledFor) },
            entries: StudentDeparturePlans.plannedEntries(for: studentID, in: context)
                .filter { comesOff($0.plannedDate) },
            openWork: hasGone || eventually ? openWorkHersAlone(studentID, in: context) : [],
            isInGroups: isInGroups(studentID, from: gone, in: context, calendar: calendar)
        )
    }

    // MARK: - Doing it

    /// Takes her off what lies after her last day (see the file comment).
    /// Does not save.
    @discardableResult
    static func carryOut(
        studentID: UUID, lastDay: Date?, in context: NSManagedObjectContext,
        now: Date = Date(), calendar: Calendar = AppCalendar.shared, ledger: DepartureSkipLedger = .synced
    ) -> Report {
        let pending = pending(studentID: studentID, lastDay: lastDay, in: context, now: now, calendar: calendar)
        var report = retract(
            studentID: studentID, plans: pending.plans, entries: pending.entries, in: context, ledger: ledger
        )
        let gone = firstDayGone(lastDay: lastDay, now: now, calendar: calendar)
        report.groupsChanged = TimetableService.takeOutOfGroups(
            studentID: studentID.uuidString, from: gone, in: context, now: now, calendar: calendar
        )
        if !pending.openWork.isEmpty {
            let entries = pending.openWork.map { WorkLogService.Entry(work: $0, status: .incomplete) }
            if (try? WorkLogService.log(entries, on: now, context: context, saveImmediately: false)) != nil {
                report.workClosed = entries.count
            }
        }
        return report
    }

    /// The departures still owed (see the file comment) whose last day has
    /// passed: each child's cascade runs now, the whole of it. Children who
    /// came back, or whose last day is still ahead, are left; so is a
    /// marker whose child isn't in the store (she may still be on her way
    /// down). Returns the children it finished. Does not save, and leaves
    /// the markers for the caller to clear once saved.
    @discardableResult
    static func finishOwed(
        in context: NSManagedObjectContext, now: Date = Date(),
        calendar: Calendar = AppCalendar.shared, ledger: DepartureSkipLedger = .synced
    ) -> [UUID] {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(
            format: "enrollmentStatusRaw != %@", CDStudent.EnrollmentStatus.enrolled.rawValue
        )
        var finished: [UUID] = []
        for student in context.safeFetch(request) where !student.isDeleted {
            guard let id = student.id, ledger.isOwed(id),
                  hasGone(lastDay: student.dateWithdrawn, now: now, calendar: calendar) else { continue }
            carryOut(
                studentID: id, lastDay: student.dateWithdrawn, in: context, now: now, calendar: calendar,
                ledger: ledger
            )
            finished.append(id)
        }
        return finished
    }

    /// The launch step: `finishOwed`, saved, then the markers cleared. Waits
    /// out a first download (the children and their plans may not be here
    /// yet) and a context holding someone else's edit. Two devices agree:
    /// what one took her off the other no longer finds once it has synced,
    /// and both write the same values. Two launching before either syncs
    /// each close her work, which leaves a second completion record for the
    /// same day (the dedup folds rows by id only); the work itself reads the
    /// same. Returns how many children it finished.
    @discardableResult
    static func finishOwedAndSave(
        in context: NSManagedObjectContext, now: Date = Date(),
        firstDownloadPending: Bool = FirstDownloadGate.isPending(), ledger: DepartureSkipLedger = .synced
    ) -> Int {
        guard !firstDownloadPending, !context.hasChanges else { return 0 }
        let finished = finishOwed(in: context, now: now, ledger: ledger)
        guard !finished.isEmpty else { return 0 }
        guard !context.hasChanges || context.safeSave() else {
            context.rollback()
            return 0
        }
        for id in finished { ledger.setOwed(false, for: id) }
        return finished.count
    }

    /// Takes her off `plans` and skips `entries`, keeping the ids of every
    /// entry this skipped (a promoted one that came off a plan included) in
    /// the ledger, so re-enrolling her finds them. Does not save. The
    /// rollover calls this for the plans and entries alone.
    @discardableResult
    static func retract(
        studentID: UUID, plans: [CDLessonAssignment], entries: [CDYearPlanEntry],
        in context: NSManagedObjectContext, ledger: DepartureSkipLedger = .synced
    ) -> Report {
        let child = studentID.uuidString
        let promoted = plans.compactMap(\.id).flatMap { planID in
            PresentationRecordCleanup.entries(promotedInto: planID.uuidString, studentIDs: [child], in: context)
        }
        var report = Report()
        report.plans = StudentDeparturePlans.retract(studentID: studentID, from: plans, in: context)
        report.entriesSkipped = StudentDeparturePlans.skip(entries: entries)
        let skipped = (entries + promoted).filter { !$0.isDeleted && $0.status == .skipped }.compactMap(\.id)
        ledger.add(skipped, for: studentID)
        return report
    }

    /// She is back: the entries her departures skipped that are still
    /// skipped go back to planned, and the list is cleared. Returns how many
    /// came back. Does not save.
    @discardableResult
    static func returning(
        studentID: UUID, in context: NSManagedObjectContext, ledger: DepartureSkipLedger = .synced
    ) -> Int {
        let ids = ledger.ids(for: studentID)
        guard !ids.isEmpty else { return 0 }
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(format: "id IN %@", ids)
        var restored = 0
        for entry in context.safeFetch(request) where !entry.isDeleted && entry.status == .skipped
            && UUID(uuidString: entry.studentID) == studentID {
            entry.status = .planned
            entry.promotedAssignmentID = nil
            restored += 1
        }
        ledger.clear(for: studentID)
        return restored
    }

    // MARK: - Pieces

    /// Her open work that is hers alone (`WorkOwnership`): her own rows and
    /// her copies of group work, not rows she shares with classmates.
    private static func openWorkHersAlone(_ studentID: UUID, in context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "studentID ==[c] %@", studentID.uuidString),
            WorkStatus.openPredicate
        ])
        let rows = context.safeFetch(request).filter { !$0.isDeleted }
        guard !rows.isEmpty else { return [] }
        let reader = WorkOwnership.Reader(covering: rows, in: context)
        return rows.filter { reader.isHersAlone($0, studentID) }
    }

    /// Whether a group from `gone` on names her: a weekly block still
    /// running, a one-off on or after it, or a day's change from it.
    private static func isInGroups(
        _ studentID: UUID, from gone: Date, in context: NSManagedObjectContext, calendar: Calendar
    ) -> Bool {
        let key = studentID.uuidString.uppercased()
        func names(_ ids: [String]) -> Bool { ids.contains { $0.uppercased() == key } }
        let blocks = context.safeFetch(CDFetchRequest(CDTimetableBlock.self))
        let inBlock = blocks.contains { block in
            guard !block.isDeleted, names(block.studentIDs) else { return false }
            if let onDay = block.onDay { return calendar.startOfDay(for: onDay) >= gone }
            return TimetableService.isRunning(block, onOrAfter: gone, calendar: calendar)
        }
        if inBlock { return true }
        let request = CDFetchRequest(CDTimetableChange.self)
        request.predicate = NSPredicate(format: "day >= %@", gone as NSDate)
        return context.safeFetch(request).contains { change in
            !change.isDeleted && change.kind == .changed && names(change.values.studentIDs)
        }
    }
}

// MARK: - The ledger

/// The year-plan entries each child's departure skipped, by child, so
/// re-enrolling her un-skips those and no others. Kept in iCloud key-value
/// storage (`SyncedPreferencesStore`), under one key per child, so the device
/// that re-enrols her months later has the list too. It also marks a
/// departure whose cascade is still owed (`setOwed`), under the same prefix
/// so it syncs the same way. Tests pass `inMemory`.
struct DepartureSkipLedger {
    static let keyPrefix = "YearPlan.departureSkips."
    /// The owed markers' keys, under `keyPrefix`: never a child's UUID, so
    /// `ids(for:)` never reads one.
    static let owedKeyPrefix = keyPrefix + "owed."

    let read: (String) -> [String]
    let write: (String, [String]?) -> Void

    static var synced: DepartureSkipLedger {
        DepartureSkipLedger(
            read: { key in SyncedPreferencesStore.shared.get(key: key) as? [String] ?? [] },
            write: { key, value in SyncedPreferencesStore.shared.set(value, forKey: key) }
        )
    }

    /// A ledger kept in memory, for tests.
    static func inMemory() -> DepartureSkipLedger {
        final class Box { var values: [String: [String]] = [:] }
        let box = Box()
        return DepartureSkipLedger(read: { box.values[$0] ?? [] }, write: { box.values[$0] = $1 })
    }

    static func key(for studentID: UUID) -> String { keyPrefix + studentID.uuidString }

    static func owedKey(for studentID: UUID) -> String { owedKeyPrefix + studentID.uuidString }

    /// Whether her departure's cascade is still owed: recorded before her
    /// last day had passed, with Remove (or by Claude).
    func isOwed(_ studentID: UUID) -> Bool { !read(Self.owedKey(for: studentID)).isEmpty }

    func setOwed(_ owed: Bool, for studentID: UUID) {
        let key = Self.owedKey(for: studentID)
        if owed {
            write(key, [studentID.uuidString])
        } else if !read(key).isEmpty {
            write(key, nil)
        }
    }

    func ids(for studentID: UUID) -> [UUID] {
        read(Self.key(for: studentID)).compactMap(UUID.init(uuidString:))
    }

    func add(_ ids: [UUID], for studentID: UUID) {
        guard !ids.isEmpty else { return }
        let key = Self.key(for: studentID)
        var stored = read(key)
        for id in ids.map(\.uuidString) where !stored.contains(id) { stored.append(id) }
        write(key, stored)
    }

    /// Forgets her skips and any owed cascade.
    func clear(for studentID: UUID) {
        write(Self.key(for: studentID), nil)
        setOwed(false, for: studentID)
    }
}
