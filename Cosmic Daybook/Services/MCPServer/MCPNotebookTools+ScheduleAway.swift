//
//  MCPNotebookTools+ScheduleAway.swift
//  Cosmic Daybook
//
//  What schedule_presentation and reschedule_presentation add to their
//  replies about the plan's children who are with another teacher that day
//  (plan "Co-teacher times when scheduling", decision 8). It never refuses:
//  the guide may book over a flexible group on purpose.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// " Lucy T is with Morah Devora 9:50–10:20." for a plan at a set time
    /// that overlaps a group; " Lucy T is away 9:50–10:20 that morning." for
    /// an untimed plan with a group in its half; "" otherwise.
    static func awaySuffix(for assignment: CDLessonAssignment, in modelContext: NSManagedObjectContext) -> String {
        guard let scheduled = assignment.scheduledFor else { return "" }
        let calendar = AppCalendar.shared
        let day = calendar.startOfDay(for: scheduled)
        guard let away = AwayTimes.days(from: day, through: day, in: modelContext, calendar: calendar)[day],
              !away.isEmpty else { return "" }
        let studentIDs = assignment.resolvedStudentIDs
        let children = AwayDay.keys(studentIDs)
        let lessonMinute: Int?
        let clashes: [AwayClash]
        switch DayHalfPlanner.moment(of: scheduled, using: calendar) {
        case .time(let moment):
            let minute = TimetableDay.minute(of: moment, calendar: calendar)
            lessonMinute = minute
            clashes = away.clashes(children: children, start: minute)
        case .half(let period):
            lessonMinute = nil
            clashes = away.away(children: children, in: period == .afternoon ? .afternoon : .morning)
        }
        guard !clashes.isEmpty else { return "" }
        let students = (try? StudentRepository(context: modelContext).fetchStudents(ids: studentIDs)) ?? []
        let names = Dictionary(
            students.compactMap { student in student.id.map { ($0.uuidString.uppercased(), student.shortName) } },
            uniquingKeysWith: { first, _ in first }
        )
        let lines = AwayText.scheduledLines(clashes, lessonMinute: lessonMinute) { names[$0] }
        return " " + lines.joined(separator: " ")
    }
}
