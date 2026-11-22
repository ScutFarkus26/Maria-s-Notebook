//
//  MCPNotebookTools+PracticeWarnings.swift
//  Cosmic Daybook
//
//  The line Claude's planning and recording tools add for a child still
//  practicing an earlier lesson in the same sequence: "Ora L still has practice
//  open on The Distributive Law (since Nov 2)." One line per child, read
//  through `WorkToShowFirst`, the same answer the app's "Before you start"
//  shows. A warning, never a refusal.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// One line per child in `studentIDs` with open work on a lesson before
    /// `lessonID` in its sequence, in the order of `studentIDs`. Empty when
    /// nobody has any.
    static func practiceWarningLines(
        lessonID: String,
        studentIDs: [UUID],
        sequences: WorkToShowFirst.Sequences? = nil,
        in modelContext: NSManagedObjectContext
    ) -> [String] {
        guard !studentIDs.isEmpty else { return [] }
        let sequences = sequences ?? WorkToShowFirst.Sequences(
            lessons: DataQueryService(context: modelContext).fetchAllLessons()
        )
        let byChild = WorkToShowFirst.find(
            lessonID: lessonID, studentIDs: Set(studentIDs), sequences: sequences, in: modelContext
        )
        guard !byChild.isEmpty else { return [] }
        let names = shortNameIndex(for: Set(byChild.keys), in: modelContext)
        var seen = Set<UUID>()
        return studentIDs.compactMap { studentID in
            guard seen.insert(studentID).inserted, let items = byChild[studentID], !items.isEmpty else { return nil }
            return practiceWarningLine(name: names[studentID] ?? "A child", items: items)
        }
    }

    /// "Ora L still has practice open on The Distributive Law (since Nov 2)."
    static func practiceWarningLine(name: String, items: [WorkToShowFirst.Item]) -> String {
        var lessons: [String] = []
        for item in items where !lessons.contains(item.lessonName) {
            lessons.append(item.lessonName)
        }
        let since = items.compactMap { $0.work.createdAt }.min().map { " (since \(monthDay($0)))" } ?? ""
        return "\(name) still has practice open on \(ListFormatter.localizedString(byJoining: lessons))\(since)."
    }

    /// Brings earlier practice forward for a plan whose day or children just
    /// changed (`PracticeCheckInTiming.followPlannedLessons`), and returns the
    /// receipt's tail: how many check-ins moved, then a warning line for each
    /// of `studentIDs` still practicing an earlier lesson. Does not save.
    static func followPractice(
        on plan: CDLessonAssignment, warningAbout studentIDs: [UUID], in modelContext: NSManagedObjectContext
    ) -> String {
        let sequences = WorkToShowFirst.Sequences(lessons: DataQueryService(context: modelContext).fetchAllLessons())
        let moved = PracticeCheckInTiming.followPlannedLessons([plan], sequences: sequences, in: modelContext)
        let warnings = practiceWarningLines(
            lessonID: plan.resolvedLessonID.uuidString, studentIDs: studentIDs, sequences: sequences, in: modelContext
        )
        let movedLine = moved == 0 ? ""
            : " \(moved) practice check-in\(moved == 1 ? "" : "s") moved earlier, to come before it."
        return movedLine + practiceWarningSuffix(warnings)
    }

    /// The warnings as a receipt's tail: a new line and one "Note:" line each, or nothing.
    static func practiceWarningSuffix(_ lines: [String]) -> String {
        lines.isEmpty ? "" : "\n" + lines.map { "Note: \($0)" }.joined(separator: "\n")
    }

    /// Each child's short name ("Maya S"), the form the guide reads.
    static func shortNameIndex(for ids: Set<UUID>, in modelContext: NSManagedObjectContext) -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        var names: [UUID: String] = [:]
        for student in modelContext.safeFetch(request) {
            guard let id = student.id, names[id] == nil else { continue }
            names[id] = StudentFormatter.displayName(for: student)
        }
        return names
    }

    /// "Maya S, Eli R", in the order given, skipping ids with no student.
    static func shortNames(_ ids: [UUID], in modelContext: NSManagedObjectContext) -> String {
        let names = shortNameIndex(for: Set(ids), in: modelContext)
        var seen = Set<UUID>()
        let listed = ids.compactMap { id in seen.insert(id).inserted ? names[id] : nil }
        return listed.isEmpty ? "no students linked" : listed.joined(separator: ", ")
    }

    /// "Nov 2".
    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = AppCalendar.shared
        formatter.timeZone = AppCalendar.shared.timeZone
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
