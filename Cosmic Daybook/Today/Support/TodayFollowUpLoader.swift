// TodayFollowUpLoader.swift
// The work check-ins the guide still owes, shaped for the Today todo list.
//
// Today already carries due check-ins in its Agenda (TodayScheduleBuilder →
// overdueSchedule/todaysSchedule), and the guide walks past them there: the
// list she acts on is the Todos section. This loader turns the same fetch into
// rows for that list, and the rules differ from the agenda's in two ways that
// matter for a follow-up LIST rather than a day's plan:
//
// - The agenda calls a check-in overdue only when the work's last touch
//   predates it, so a check-in the guide has been near but not closed drops
//   out. A list must not hide what is still owed: here `scheduled` and dated
//   before the selected day is overdue, full stop; on the selected day is due.
// - The agenda drops work whose owner is missing from the enrolled roster, so
//   a withdrawn child's check-in is invisible. Here it stays, marked — leftover
//   work on a departed child is exactly the thing the guide needs to close,
//   and a row she cannot see is a row she cannot close.
//
// One row per work: its earliest due check-in. A row is judged by whose it
// is (bug hunt 2026-10-12, #46): a linked copy — one of the rows Quick New
// Work and assign_work make, one per child, each naming the whole group — is
// its owner's alone, so the level filter and the "left" mark follow her, and
// her classmates are named only as company ("with Eli R, Ana T"). A genuinely
// shared row (project work) is everyone's on it. `WorkVisibility` tells the
// two apart, as the checklist and the Work column do.
//
// Pure after the fetches the caller already holds, so `build` is
// unit-testable without a view model.

import CoreData
import Foundation

/// One due or overdue work check-in, with everyone the work names.
struct WorkCheckInFollowUp: Identifiable {
    let id: UUID
    let checkIn: CDWorkCheckIn
    let work: CDWorkModel
    /// `AppCalendar.startOfDay(checkIn.date)`.
    let dueDay: Date
    /// `dueDay` is before the selected day.
    let isOverdue: Bool
    /// Everyone on the work, owner first (`WorkGrouping.studentIDs(of:)`).
    let studentIDs: [UUID]
    /// Whose row it is: the owner alone on a linked copy (each classmate has
    /// a copy of her own), everyone on a genuinely shared row.
    let countedStudentIDs: [UUID]
    /// The subset of `countedStudentIDs` whose enrollment is not `.enrolled`.
    let departedStudentIDs: Set<UUID>

    init(
        id: UUID,
        checkIn: CDWorkCheckIn,
        work: CDWorkModel,
        dueDay: Date,
        isOverdue: Bool,
        studentIDs: [UUID],
        countedStudentIDs: [UUID]? = nil,
        departedStudentIDs: Set<UUID>
    ) {
        self.id = id
        self.checkIn = checkIn
        self.work = work
        self.dueDay = dueDay
        self.isOverdue = isOverdue
        self.studentIDs = studentIDs
        self.countedStudentIDs = countedStudentIDs ?? studentIDs
        self.departedStudentIDs = departedStudentIDs
    }

    var hasDepartedParticipant: Bool { !departedStudentIDs.isEmpty }

    /// Classmates named on a linked copy who have copies of their own.
    var companionIDs: [UUID] {
        studentIDs.filter { !countedStudentIDs.contains($0) }
    }
}

enum TodayFollowUpLoader {

    /// Every former student — withdrawn or transferred — in `roster`, keyed
    /// by id. Pure: the roster is the view model's snapshot
    /// (`TodayCacheManager.departedStudents`), not a fetch of its own.
    static func departedStudents(in roster: [CDStudent]) -> [UUID: CDStudent] {
        let enrolled = CDStudent.EnrollmentStatus.enrolled.rawValue
        var byID: [UUID: CDStudent] = [:]
        for student in roster where student.enrollmentStatusRaw != enrolled {
            guard let id = student.id else { continue }
            byID[id] = student
        }
        return byID
    }

    // The follow-up rows for `day`, from the work fetch `reload()` already
    // holds.
    //
    // - fetch: `TodayDataFetcher.fetchWorkData` for the day (nil = fetch failed → no rows).
    // - day/nextDay: the selected day's bounds.
    // - studentsByID: the enrolled cache; departedStudentsByID: former students.
    // - levelFilter: `.all` keeps every row; otherwise a row stays when a
    //   child it counts for (see the file comment) matches.
    // - context: when given, the due rows' lessons are read once
    //   (`WorkVisibility(covering:in:)`), so a copy whose classmates have
    //   closed theirs still reads as a copy. Without it, only the open rows in
    //   `fetch` are compared, and nothing touches a context.
    // swiftlint:disable:next function_parameter_count
    static func build(
        fetch: TodayDataFetcher.WorkFetchResult?,
        day: Date,
        nextDay: Date,
        studentsByID: [UUID: CDStudent],
        departedStudentsByID: [UUID: CDStudent],
        levelFilter: LevelFilter,
        context: NSManagedObjectContext? = nil
    ) -> [WorkCheckInFollowUp] {
        guard let fetch else { return [] }
        let selectedDay = AppCalendar.startOfDay(day)
        var rows: [WorkCheckInFollowUp] = []

        let due: [DueCheckIn] = fetch.workItems.compactMap { work in
            guard let workID = work.id,
                  let checkIn = earliestDueCheckIn(fetch.checkInsByWork[workID] ?? [], before: nextDay),
                  let checkInDate = checkIn.date else { return nil }
            return DueCheckIn(workID: workID, work: work, checkIn: checkIn, date: checkInDate)
        }
        let visibility = context.map { WorkVisibility(covering: due.map(\.work), in: $0) }
            ?? WorkVisibility(rows: fetch.workItems)

        for entry in due {
            let work = entry.work
            let studentIDs = WorkGrouping.studentIDs(of: work)
            let counted = studentIDs.filter { visibility.isVisible(work, to: $0) }
            let named = counted.compactMap { id -> (id: UUID, student: CDStudent)? in
                guard let student = studentsByID[id] ?? departedStudentsByID[id] else { return nil }
                return (id, student)
            }
            // No child the notebook knows (a hidden test id, or garbage) —
            // the same rule the agenda applies. A copy is its owner's, so a
            // hidden test child's copy goes even when it names classmates.
            guard !named.isEmpty else { continue }
            guard levelFilter == .all || named.contains(where: { levelFilter.matches($0.student.level) }) else {
                continue
            }

            let departed = Set(named.filter { !$0.student.isEnrolled }.map(\.id))
            let dueDay = AppCalendar.startOfDay(entry.date)
            rows.append(WorkCheckInFollowUp(
                id: entry.checkIn.id ?? entry.workID,
                checkIn: entry.checkIn,
                work: work,
                dueDay: dueDay,
                isOverdue: dueDay < selectedDay,
                studentIDs: studentIDs,
                countedStudentIDs: counted,
                departedStudentIDs: departed
            ))
        }

        return rows.sorted { lhs, rhs in
            if lhs.dueDay != rhs.dueDay { return lhs.dueDay < rhs.dueDay }
            let lhsOwner = ownerSortKey(lhs, studentsByID: studentsByID, departedStudentsByID: departedStudentsByID)
            let rhsOwner = ownerSortKey(rhs, studentsByID: studentsByID, departedStudentsByID: departedStudentsByID)
            if lhsOwner != rhsOwner { return lhsOwner < rhsOwner }
            return lhs.work.title.localizedCaseInsensitiveCompare(rhs.work.title) == .orderedAscending
        }
    }

    // MARK: - Helpers

    /// A work row with its earliest due check-in.
    private struct DueCheckIn {
        let workID: UUID
        let work: CDWorkModel
        let checkIn: CDWorkCheckIn
        let date: Date
    }

    /// The earliest check-in still `scheduled` and dated before `nextDay`.
    private static func earliestDueCheckIn(_ checkIns: [CDWorkCheckIn], before nextDay: Date) -> CDWorkCheckIn? {
        checkIns
            .filter { $0.status == .scheduled && ($0.date.map { $0 < nextDay } ?? false) }
            .min { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// "first last" of the owner, lowercased, for a stable order within a day.
    private static func ownerSortKey(
        _ row: WorkCheckInFollowUp,
        studentsByID: [UUID: CDStudent],
        departedStudentsByID: [UUID: CDStudent]
    ) -> String {
        guard let ownerID = row.studentIDs.first,
              let owner = studentsByID[ownerID] ?? departedStudentsByID[ownerID] else { return "" }
        return owner.fullName.lowercased()
    }
}
