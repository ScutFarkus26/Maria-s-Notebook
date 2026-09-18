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
// One row per work: its earliest due check-in. Pure after the two fetches the
// caller already holds, so `build` is unit-testable without a view model.

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
    /// The subset of `studentIDs` whose enrollment is not `.enrolled`.
    let departedStudentIDs: Set<UUID>

    var hasDepartedParticipant: Bool { !departedStudentIDs.isEmpty }
}

enum TodayFollowUpLoader {

    /// Every former student — withdrawn or transferred — keyed by id. One
    /// fetch; the enrolled roster is the view model's cache and is not
    /// re-read here.
    static func fetchDepartedStudents(context: NSManagedObjectContext) -> [UUID: CDStudent] {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(
            format: "enrollmentStatusRaw != %@", CDStudent.EnrollmentStatus.enrolled.rawValue
        )
        request.fetchLimit = 500
        var byID: [UUID: CDStudent] = [:]
        for student in context.safeFetch(request) {
            guard let id = student.id else { continue }
            byID[id] = student
        }
        return byID
    }

    // The follow-up rows for `day`, from the work fetch `reload()` already
    // holds. Pure: no context access.
    //
    // - fetch: `TodayDataFetcher.fetchWorkData` for the day (nil = fetch failed → no rows).
    // - day/nextDay: the selected day's bounds.
    // - studentsByID: the enrolled cache; departedStudentsByID: former students.
    // - levelFilter: `.all` keeps every row; otherwise a row stays when any
    //   named child in either map matches.
    // swiftlint:disable:next function_parameter_count
    static func build(
        fetch: TodayDataFetcher.WorkFetchResult?,
        day: Date,
        nextDay: Date,
        studentsByID: [UUID: CDStudent],
        departedStudentsByID: [UUID: CDStudent],
        levelFilter: LevelFilter
    ) -> [WorkCheckInFollowUp] {
        guard let fetch else { return [] }
        let selectedDay = AppCalendar.startOfDay(day)
        var rows: [WorkCheckInFollowUp] = []

        for work in fetch.workItems {
            guard let workID = work.id,
                  let checkIn = earliestDueCheckIn(fetch.checkInsByWork[workID] ?? [], before: nextDay),
                  let checkInDate = checkIn.date else { continue }

            let studentIDs = WorkGrouping.studentIDs(of: work)
            let named = studentIDs.compactMap { id -> (id: UUID, student: CDStudent)? in
                guard let student = studentsByID[id] ?? departedStudentsByID[id] else { return nil }
                return (id, student)
            }
            // No child the notebook knows (a hidden test id, or garbage) —
            // the same rule the agenda applies.
            guard !named.isEmpty else { continue }
            guard levelFilter == .all || named.contains(where: { levelFilter.matches($0.student.level) }) else {
                continue
            }

            let departed = Set(named.filter { !$0.student.isEnrolled }.map(\.id))
            let dueDay = AppCalendar.startOfDay(checkInDate)
            rows.append(WorkCheckInFollowUp(
                id: checkIn.id ?? workID,
                checkIn: checkIn,
                work: work,
                dueDay: dueDay,
                isOverdue: dueDay < selectedDay,
                studentIDs: studentIDs,
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
        return "\(owner.firstName) \(owner.lastName)".lowercased()
    }
}
