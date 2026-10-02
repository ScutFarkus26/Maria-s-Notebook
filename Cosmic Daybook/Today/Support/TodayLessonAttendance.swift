// TodayLessonAttendance.swift
// Who on a lesson is here, read against the day's absences.
//
// A lesson row names its children as chips; the ones attendance marks absent
// are struck through and labeled, and the row ends with "6 of 7 here" ("all 4
// here" when nobody is missing) once the day's attendance is taken. The Lessons header counts the absent
// children across the day's lessons and says how many lessons are given.
//
// Value inputs only — the ids on the lesson, the day's absent set
// (`TodayViewModel.absentStudentIDs`) — so every string here is testable
// without a store.

import Foundation

nonisolated struct TodayLessonAttendance: Equatable, Sendable {
    nonisolated struct Child: Equatable, Identifiable, Sendable {
        let id: UUID
        let isAbsent: Bool
    }

    /// The lesson's children, in the lesson's own order.
    let children: [Child]

    init(studentIDs: [UUID], absent: Set<UUID>) {
        children = studentIDs.map { Child(id: $0, isAbsent: absent.contains($0)) }
    }

    var absentIDs: [UUID] { children.filter(\.isAbsent).map(\.id) }
    var hasAbsent: Bool { children.contains(where: \.isAbsent) }

    /// "6 of 7 here", "all 4 here", or "here" for a lesson of one. Nil for a
    /// lesson with nobody on it.
    var hereText: String? {
        let total = children.count
        guard total > 0 else { return nil }
        let here = children.count(where: { !$0.isAbsent })
        if here == total { return total == 1 ? "here" : "all \(total) here" }
        return "\(here) of \(total) here"
    }

    /// `hereText` once the day's attendance is taken, else nil: before the
    /// first mark nobody is absent yet, so every lesson would read "all N here".
    func hereText(attendanceTaken: Bool) -> String? {
        attendanceTaken ? hereText : nil
    }

    // MARK: - Across the day's lessons

    /// Every child marked absent on at least one of these lessons, once each.
    static func absentChildren(onLessons studentIDs: [[UUID]], absent: Set<UUID>) -> Set<UUID> {
        Set(studentIDs.joined()).intersection(absent)
    }

    /// "Lessons · 0 of 4 given" — the header's count.
    static func givenText(given: Int, total: Int) -> String {
        "\(given) of \(total) given"
    }

    /// "3 children on today's lessons are absent", for the header's move link.
    static func absentSummary(count: Int) -> String {
        count == 1
            ? "1 child on today's lessons is absent"
            : "\(count) children on today's lessons are absent"
    }
}
