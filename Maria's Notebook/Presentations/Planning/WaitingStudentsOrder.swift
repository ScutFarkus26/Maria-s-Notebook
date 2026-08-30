// WaitingStudentsOrder.swift
// Who has been waiting longest for a lesson, in order.
//
// Kept free of SwiftUI and of Core Data fetching so the ordering — which is the
// part that decides whether a child is visible at all — can be tested directly.
//
// One subtlety this type exists to contain: the app has four different ways of
// saying "this child has never been taught" (`Int.max`, `-1`, `nil`, and a
// missing dictionary key). Reading the wrong one silently sorts never-taught
// children to the *bottom*, which is the opposite of the point. Everything is
// normalised to `nil` here, at the boundary.

import CoreData
import Foundation

/// Which children the rail is showing.
enum WaitingStudentsScope: String, CaseIterable, Identifiable, Sendable {
    /// Every enrolled child, however recently taught.
    case everyone
    /// Only children with no lesson on the calendar from today onward.
    case unscheduled

    var id: Self { self }

    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .unscheduled: "Unscheduled"
        }
    }

    static func resolved(rawValue: String?) -> Self {
        guard let rawValue, let scope = Self(rawValue: rawValue) else { return .everyone }
        return scope
    }
}

/// One row: a child and how long they have waited.
struct WaitingStudent: Identifiable {
    let student: CDStudent
    /// School days since their last lesson, or `nil` if they have never had one.
    let daysWaiting: Int?

    var id: NSManagedObjectID { student.objectID }

    /// Never-taught reads as the most urgent thing on the list.
    var isNeverTaught: Bool { daysWaiting == nil }
}

enum WaitingStudentsOrder {

    /// Normalises every "never taught" spelling in the app to `nil`.
    ///
    /// `PresentationsViewModel` uses `Int.max`, `StudentsViewModel` uses `-1`,
    /// and a child missing from the map has simply never been counted. All three
    /// mean the same thing and must sort together.
    static func daysWaiting(from raw: Int?) -> Int? {
        guard let raw, raw >= 0, raw != Int.max else { return nil }
        return raw
    }

    /// Orders `students` by who has gone longest without a lesson.
    ///
    /// - Parameters:
    ///   - daysSince: the caller's already-built map. Pass one map only — mixing
    ///     two of them mixes two sentinel conventions.
    ///   - studentIDsWithUpcomingLessons: children who already have something on
    ///     the calendar from today onward, used only by `.unscheduled`.
    static func ordered(
        students: [CDStudent],
        daysSince: [UUID: Int],
        studentIDsWithUpcomingLessons: Set<UUID>,
        scope: WaitingStudentsScope,
        search: String = ""
    ) -> [WaitingStudent] {
        let query = search.trimmed().lowercased()

        return students
            .filter { student in
                guard let id = student.id else { return false }
                if scope == .unscheduled, studentIDsWithUpcomingLessons.contains(id) {
                    return false
                }
                guard !query.isEmpty else { return true }
                return StudentFormatter.displayName(for: student).lowercased().contains(query)
            }
            .map { student in
                WaitingStudent(
                    student: student,
                    daysWaiting: daysWaiting(from: student.id.flatMap { daysSince[$0] })
                )
            }
            .sorted(by: isOrderedBefore)
    }

    /// Never taught first, then longest wait, then by name so that children who
    /// have waited the same number of days do not reshuffle between refreshes.
    static func isOrderedBefore(_ lhs: WaitingStudent, _ rhs: WaitingStudent) -> Bool {
        switch (lhs.daysWaiting, rhs.daysWaiting) {
        case (nil, nil):
            break
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (left?, right?):
            if left != right { return left > right }
        }
        return StudentFormatter.displayName(for: lhs.student)
            .localizedCaseInsensitiveCompare(StudentFormatter.displayName(for: rhs.student))
            == .orderedAscending
    }

    /// The children who already have a lesson coming up.
    ///
    /// Deliberately *not* `TriageBucket.scheduled`, which counts any ungiven
    /// assignment with a date — including one scheduled months ago that never
    /// happened. A child whose only booking is a lesson that never got given has
    /// not been scheduled in any sense the guide means, and hiding them would
    /// make them permanently invisible on this list.
    static func studentIDsWithUpcomingLessons(
        in assignments: [CDLessonAssignment],
        asOf now: Date = Date()
    ) -> Set<UUID> {
        let today = AppCalendar.startOfDay(now)
        var ids = Set<UUID>()
        for assignment in assignments {
            guard let scheduledFor = assignment.scheduledFor, !assignment.isGiven else { continue }
            guard AppCalendar.startOfDay(scheduledFor) >= today else { continue }
            ids.formUnion(assignment.resolvedStudentIDs)
        }
        return ids
    }
}
