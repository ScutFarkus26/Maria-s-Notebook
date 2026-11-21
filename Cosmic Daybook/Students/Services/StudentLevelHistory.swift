// StudentLevelHistory.swift
// A child's level history (domain logic review 2026-11-20, A8; plan "Domain
// logic fixes", Decision 13). Every change of level is a dated step, a
// `CDLevelChange`, written here and nowhere else: the student page's level
// menu and Claude's update_student (through `StudentRepository.updateStudent`),
// the school-year rollover and the roster import. A change undone the same
// day leaves no step, so a mis-tap leaves no history, and a monthly report
// reads the level she had that month.
//
// The student's own `previousLevelRaw` and `dateLastPromoted` (one step, all
// there was before schema 25) are kept matching the latest step, for older
// builds and the backups they read.

import CoreData
import Foundation

enum StudentLevelHistory {

    /// One step, from a `CDLevelChange` or, for a child whose history began
    /// before schema 25, from her own two fields.
    struct Step: Equatable {
        let from: CDStudent.Level
        let to: CDStudent.Level
        /// The day it took effect.
        let on: Date

        /// Whether she moved up the ladder (Lower → Upper), not down.
        var isPromotion: Bool {
            let order = CDStudent.Level.allCases
            return (order.firstIndex(of: to) ?? 0) > (order.firstIndex(of: from) ?? 0)
        }
    }

    /// Moves her to `level`, effective `day`, and records the step. A second
    /// change the same day amends that day's step instead of adding one, and
    /// when it brings her back to where the day began, the step goes. Does
    /// nothing when she is already at `level`. Does not save.
    static func change(
        _ student: CDStudent, to level: CDStudent.Level, on day: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) {
        guard level != student.level, let context = student.managedObjectContext,
              let studentID = student.id?.uuidString else { return }
        var rows = steps(for: studentID, in: context)
        // A change dated before her latest step (a rollover dated the last
        // day of school, after a change made since) takes that step's day,
        // so the history still ends at the level she is at.
        let latestDay = rows.compactMap(\.changedOn).max().map(calendar.startOfDay(for:))
        let effective = max(calendar.startOfDay(for: day), latestDay ?? .distantPast)
        if rows.isEmpty, let legacy = legacyStep(of: student, calendar: calendar), legacy.on < effective {
            // Her one recorded promotion becomes the first step, so undoing
            // today's change gives the profile back its "Promoted" line.
            rows.append(insert(legacy, studentID: studentID, in: context))
        }

        if let sameDay = rows.last(where: { row in
            row.changedOn.map { calendar.isDate($0, inSameDayAs: effective) } ?? false
        }) {
            sameDay.toLevelRaw = level.rawValue
            sameDay.modifiedAt = Date()
            if sameDay.fromLevelRaw == sameDay.toLevelRaw {
                context.delete(sameDay)
                rows.removeAll { $0 === sameDay }
            }
        } else {
            let step = Step(from: student.level, to: level, on: effective)
            rows.append(insert(step, studentID: studentID, in: context))
            rows.sort(by: isEarlier)
        }

        student.level = level
        let latest = rows.last.flatMap(step(of:))
        student.previousLevelRaw = latest?.from.rawValue
        student.dateLastPromoted = latest?.on
    }

    /// Her latest step: the newest `CDLevelChange`, or her own two fields
    /// when she has none. Nil when no change was ever recorded.
    static func latestStep(of student: CDStudent, calendar: Calendar = AppCalendar.shared) -> Step? {
        guard let context = student.managedObjectContext, let studentID = student.id?.uuidString else {
            return legacyStep(of: student, calendar: calendar)
        }
        let rows = steps(for: studentID, in: context)
        return rows.last.flatMap(step(of:)) ?? legacyStep(of: student, calendar: calendar)
    }

    /// The level she had on `day`: the step in effect then, or before her
    /// first step the level it started from. A child with no history has
    /// always been at her level.
    static func level(
        of student: CDStudent, on day: Date, calendar: Calendar = AppCalendar.shared
    ) -> CDStudent.Level {
        var history: [Step] = []
        if let context = student.managedObjectContext, let studentID = student.id?.uuidString {
            history = steps(for: studentID, in: context).compactMap(step(of:))
        }
        if history.isEmpty, let legacy = legacyStep(of: student, calendar: calendar) { history = [legacy] }
        let start = calendar.startOfDay(for: day)
        if let inEffect = history.last(where: { $0.on <= start }) { return inEffect.to }
        return history.first?.from ?? student.level
    }

    // MARK: - Rows

    private static func steps(for studentID: String, in context: NSManagedObjectContext) -> [CDLevelChange] {
        let request = CDFetchRequest(CDLevelChange.self)
        request.predicate = NSPredicate(format: "studentID ==[c] %@", studentID)
        return context.safeFetch(request).filter { !$0.isDeleted && $0.changedOn != nil }.sorted(by: isEarlier)
    }

    /// Oldest first; two steps on one day (two devices) by when they were made.
    private static func isEarlier(_ lhs: CDLevelChange, _ rhs: CDLevelChange) -> Bool {
        let left = lhs.changedOn ?? .distantPast
        let right = rhs.changedOn ?? .distantPast
        if left != right { return left < right }
        return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
    }

    private static func step(of row: CDLevelChange) -> Step? {
        guard let to = row.toLevel, let on = row.changedOn else { return nil }
        return Step(from: row.fromLevel ?? to, to: to, on: on)
    }

    private static func legacyStep(of student: CDStudent, calendar: Calendar) -> Step? {
        guard let from = student.previousLevel, let on = student.dateLastPromoted, from != student.level else {
            return nil
        }
        return Step(from: from, to: student.level, on: calendar.startOfDay(for: on))
    }

    @discardableResult
    private static func insert(_ step: Step, studentID: String, in context: NSManagedObjectContext) -> CDLevelChange {
        let row = CDLevelChange(context: context)
        row.studentID = studentID
        row.fromLevelRaw = step.from.rawValue
        row.toLevelRaw = step.to.rawValue
        row.changedOn = step.on
        return row
    }
}
