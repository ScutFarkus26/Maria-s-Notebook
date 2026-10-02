// TodayLessonAttendance.swift
// Who on a lesson is here, read against the day's absences.
//
// A lesson row names its children as chips; the ones attendance marks absent
// are struck through and labeled, and the row ends with "6 of 7 here" ("all 4
// here" when everyone is) once the day's attendance is taken. Here means in
// the room — marked present or late — so a child not marked yet isn't counted
// ("0 of 1 here" until she is). The Lessons header counts the absent
// children across the day's lessons and says how many lessons are given.
//
// Value inputs only — the ids on the lesson, the day's absent and here sets
// (`TodayViewModel.absentStudentIDs` / `hereStudentIDs`) — so every string here is testable
// without a store.

import Foundation

nonisolated struct TodayLessonAttendance: Equatable, Sendable {
    nonisolated struct Child: Equatable, Identifiable, Sendable {
        let id: UUID
        let isAbsent: Bool
        /// Marked present or late. Neither this nor absent: not marked yet.
        let isHere: Bool
    }

    /// The lesson's children, in the lesson's own order.
    let children: [Child]

    init(studentIDs: [UUID], absent: Set<UUID>, here: Set<UUID> = []) {
        children = studentIDs.map {
            Child(id: $0, isAbsent: absent.contains($0), isHere: here.contains($0))
        }
    }

    var absentIDs: [UUID] { children.filter(\.isAbsent).map(\.id) }
    var hasAbsent: Bool { children.contains(where: \.isAbsent) }

    /// "6 of 7 here", "all 4 here", or "here" for a lesson of one, counting
    /// the children marked present or late. Nil for a lesson with nobody on it.
    var hereText: String? {
        let total = children.count
        guard total > 0 else { return nil }
        let here = children.count(where: \.isHere)
        if here == total { return total == 1 ? "here" : "all \(total) here" }
        return "\(here) of \(total) here"
    }

    /// `hereText` once the day's attendance is taken, else nil: before the
    /// first mark nobody is here yet, so every lesson would read "0 of N here".
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
