import Foundation
import OSLog
import CoreData

@MainActor
enum PlanningActions {
    private static let logger = Logger.planning

    static func moveToInbox(_ la: CDLessonAssignment, context: NSManagedObjectContext) {
        la.scheduledFor = nil
        la.stateRaw = LessonAssignmentState.draft.rawValue
        la.modifiedAt = Date()
        Task { @MainActor in context.safeSave() }
    }

    static func planNextLesson(
        for la: CDLessonAssignment,
        lessons: [CDLesson],
        students: [CDStudent],
        lessonAssignments: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) {
        let result = PlanNextLessonService.planNextLesson(
            for: la,
            allLessons: lessons,
            allStudents: students,
            existingLessonAssignments: lessonAssignments,
            context: context
        )

        if case .success = result {
            context.safeSave()
        }
    }

    /// Push all scheduled lessons that include at least one absent student to the next school day.
    static func pushLessonsWithAbsentStudents(in days: [Date], calendar: Calendar, context: NSManagedObjectContext) async {
        guard let firstDay = days.first else { return }
        let start = calendar.startOfDay(for: firstDay)
        let lastDay = days.last ?? firstDay
        let endDate = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let end = calendar.startOfDay(for: endDate)
        let scheduledRaw = LessonAssignmentState.scheduled.rawValue
        let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(
            format: "stateRaw == %@ AND scheduledFor >= %@ AND scheduledFor < %@",
            scheduledRaw, start as CVarArg, end as CVarArg
        )
        let scheduled: [CDLessonAssignment] = context.safeFetch(descriptor)

        // Fetch attendance records for the same range
        let attDescriptor: NSFetchRequest<CDAttendanceRecord> = NSFetchRequest(entityName: "AttendanceRecord")
        attDescriptor.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as CVarArg, end as CVarArg)
        let attendance: [CDAttendanceRecord] = context.safeFetch(attDescriptor)

        // Build lookup: (dayStart, studentID) -> status
        var attendanceMap: [Date: [UUID: AttendanceStatus]] = [:]
        for rec in attendance {
            guard let recDate = rec.date else { continue }
            let day = calendar.startOfDay(for: recDate)
            var inner = attendanceMap[day] ?? [:]
            if let studentIDUUID = UUID(uuidString: rec.studentID) {
                inner[studentIDUUID] = rec.status
                attendanceMap[day] = inner
            }
        }

        var changed = false
        for la in scheduled {
            guard let when = la.scheduledFor else { continue }
            let day = calendar.startOfDay(for: when)
            let statuses = attendanceMap[day] ?? [:]
            let anyAbsent = la.resolvedStudentIDs.contains { sid in
                if let st = statuses[sid] { return st == .absent } else { return false }
            }
            guard anyAbsent else { continue }

            let nextDay = await SchoolCalendar.nextSchoolDay(after: day, using: context)
            let comps = calendar.dateComponents([.hour, .minute, .second], from: when)
            if let newDate = calendar.date(
                bySettingHour: comps.hour ?? 9,
                minute: comps.minute ?? 0,
                second: comps.second ?? 0,
                of: nextDay
            ) {
                la.scheduledFor = newDate
                la.modifiedAt = Date()
                changed = true
            }
        }
        if changed { context.safeSave() }
    }

    /// Push all scheduled lessons forward by one school day, preserving their time-of-day.
    static func pushAllLessonsByOneDay(in days: [Date], calendar: Calendar, context: NSManagedObjectContext) async {
        guard let firstDay = days.first else { return }
        let start = calendar.startOfDay(for: firstDay)
        let lastDay = days.last ?? firstDay
        let endDate = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let end = calendar.startOfDay(for: endDate)
        let scheduledRaw = LessonAssignmentState.scheduled.rawValue
        let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(
            format: "stateRaw == %@ AND scheduledFor >= %@ AND scheduledFor < %@",
            scheduledRaw, start as CVarArg, end as CVarArg
        )
        let scheduled: [CDLessonAssignment] = context.safeFetch(descriptor)

        var changed = false
        for la in scheduled {
            guard let when = la.scheduledFor else { continue }
            let day = calendar.startOfDay(for: when)
            let nextDay = await SchoolCalendar.nextSchoolDay(after: day, using: context)
            let comps = calendar.dateComponents([.hour, .minute, .second], from: when)
            if let newDate = calendar.date(
                bySettingHour: comps.hour ?? 9,
                minute: comps.minute ?? 0,
                second: comps.second ?? 0,
                of: nextDay
            ) {
                la.scheduledFor = newDate
                la.modifiedAt = Date()
                changed = true
            }
        }
        if changed { context.safeSave() }
    }
}
