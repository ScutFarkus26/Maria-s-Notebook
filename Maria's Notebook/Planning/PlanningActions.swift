import Foundation
import SwiftData
import OSLog

@MainActor
enum PlanningActions {
    private static let logger = Logger.planning
    static func moveToInbox(_ sl: StudentLesson, context: ModelContext) {
        sl.setScheduledFor(nil, using: AppCalendar.shared)
        Task { @MainActor in context.safeSave() }
    }

    static func planNextLesson(for sl: StudentLesson, lessons: [Lesson], students: [Student], studentLessons: [StudentLesson], context: ModelContext) {
        // Convert StudentLesson to LessonAssignment for the service call
        // Find the corresponding LessonAssignment via migratedFromStudentLessonID
        let slIDString = sl.id.uuidString  // Compute outside predicate
        let laDescriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { la in
                la.migratedFromStudentLessonID == slIDString
            }
        )
        let la: LessonAssignment
        do {
            guard let fetchedLA = try context.fetch(laDescriptor).first else {
                return  // Lesson assignment not found, skip
            }
            la = fetchedLA
        } catch {
            logger.warning("Failed to fetch lesson assignment: \(error)")
            return
        }

        // Fetch all LessonAssignments for duplicate checking
        let allLAs: [LessonAssignment]
        do {
            allLAs = try context.fetch(FetchDescriptor<LessonAssignment>())
        } catch {
            logger.warning("Failed to fetch lesson assignments: \(error)")
            allLAs = []
        }
        
        let result = PlanNextLessonService.planNextLesson(
            for: la,
            allLessons: lessons,
            allStudents: students,
            existingLessonAssignments: allLAs,
            context: context
        )

        if case .success = result {
            context.safeSave()
        }
    }
    
    static func planNextLesson(for la: LessonAssignment, lessons: [Lesson], students: [Student], lessonAssignments: [LessonAssignment], context: ModelContext) {
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
    /// - Parameters:
    ///   - days: School days to consider (start-of-day dates). Lessons scheduled on these days will be evaluated.
    ///   - calendar: Calendar used to compute day boundaries and preserve time-of-day.
    ///   - context: ModelContext for fetching and saving.
    static func pushLessonsWithAbsentStudents(in days: [Date], calendar: Calendar, context: ModelContext) async {
        guard let firstDay = days.first else { return }
        let start = calendar.startOfDay(for: firstDay)
        let lastDay = days.last ?? firstDay
        let endDate = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let end = calendar.startOfDay(for: endDate)
        // Fetch scheduled, un-given lessons within range
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { sl in
                sl.isPresented == false && sl.givenAt == nil && sl.scheduledFor != nil && sl.scheduledFor! >= start && sl.scheduledFor! < end
            }
        )
        let scheduled: [StudentLesson] = context.safeFetch(descriptor)

        // Fetch attendance records for the same range
        let attDescriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate { rec in rec.date >= start && rec.date < end }
        )
        let attendance: [AttendanceRecord] = context.safeFetch(attDescriptor)

        // Build lookup: (dayStart, studentID) -> status
        var attendanceMap: [Date: [UUID: AttendanceStatus]] = [:]
        for rec in attendance {
            let day = calendar.startOfDay(for: rec.date)
            var inner = attendanceMap[day] ?? [:]
            // CloudKit compatibility: Convert String studentID to UUID
            if let studentIDUUID = UUID(uuidString: rec.studentID) {
                inner[studentIDUUID] = rec.status
                attendanceMap[day] = inner
            }
        }

        var changed = false
        for sl in scheduled {
            guard let when = sl.scheduledFor else { continue }
            let day = calendar.startOfDay(for: when)
            let statuses = attendanceMap[day] ?? [:]
            // If any participant is absent on that day, push to next school day
            let anyAbsent = sl.resolvedStudentIDs.contains { sid in
                if let st = statuses[sid] { return st == .absent } else { return false }
            }
            guard anyAbsent else { continue }

            // Compute next school day and preserve time components
            let nextDay = await SchoolCalendar.nextSchoolDay(after: day, using: context)
            let comps = calendar.dateComponents([.hour, .minute, .second], from: when)
            if let newDate = calendar.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: comps.second ?? 0, of: nextDay) {
                sl.setScheduledFor(newDate, using: AppCalendar.shared)
                changed = true
            }
        }
        if changed { context.safeSave() }
    }

    /// Push all scheduled lessons forward by one school day, preserving their time-of-day.
    /// - Parameters:
    ///   - days: School days to consider (start-of-day dates). Only lessons scheduled on these days are moved.
    ///   - calendar: Calendar used to compute day boundaries and preserve time-of-day.
    ///   - context: ModelContext for fetching and saving.
    static func pushAllLessonsByOneDay(in days: [Date], calendar: Calendar, context: ModelContext) async {
        guard let firstDay = days.first else { return }
        let start = calendar.startOfDay(for: firstDay)
        let lastDay = days.last ?? firstDay
        let endDate = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let end = calendar.startOfDay(for: endDate)
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { sl in
                sl.isPresented == false && sl.givenAt == nil && sl.scheduledFor != nil && sl.scheduledFor! >= start && sl.scheduledFor! < end
            }
        )
        let scheduled: [StudentLesson] = context.safeFetch(descriptor)

        var changed = false
        for sl in scheduled {
            guard let when = sl.scheduledFor else { continue }
            let day = calendar.startOfDay(for: when)
            let nextDay = await SchoolCalendar.nextSchoolDay(after: day, using: context)
            let comps = calendar.dateComponents([.hour, .minute, .second], from: when)
            if let newDate = calendar.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: comps.second ?? 0, of: nextDay) {
                sl.setScheduledFor(newDate, using: AppCalendar.shared)
                changed = true
            }
        }
        if changed { context.safeSave() }
    }
}
