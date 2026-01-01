import Foundation
import SwiftData

enum PlanningActions {
    static func moveToInbox(_ sl: StudentLesson, context: ModelContext) {
        sl.setScheduledFor(nil, using: AppCalendar.shared)
        Task { @MainActor in try? context.save() }
    }

    static func planNextLesson(for sl: StudentLesson, lessons: [Lesson], students: [Student], studentLessons: [StudentLesson], context: ModelContext) {
        guard let currentLesson = lessons.first(where: { $0.id == sl.lessonID }) else { return }
        let currentSubject = currentLesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = currentLesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return }

        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }

        guard let idx = candidates.firstIndex(where: { $0.id == currentLesson.id }), idx + 1 < candidates.count else { return }
        let next = candidates[idx + 1]

        let sameStudents = Set(sl.resolvedStudentIDs)
        let exists = studentLessons.contains { existing in
            existing.resolvedLessonID == next.id && Set(existing.resolvedStudentIDs) == sameStudents && existing.givenAt == nil
        }
        guard !exists else { return }

        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: next.id,
            studentIDs: sl.studentIDs.compactMap { UUID(uuidString: $0) },
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newStudentLesson.students = students.filter { sameStudents.contains($0.id) }
        newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
        newStudentLesson.syncSnapshotsFromRelationships()
        context.insert(newStudentLesson)
        try? context.save()
    }

    /// Push all scheduled lessons that include at least one absent student to the next school day.
    /// - Parameters:
    ///   - days: School days to consider (start-of-day dates). Lessons scheduled on these days will be evaluated.
    ///   - calendar: Calendar used to compute day boundaries and preserve time-of-day.
    ///   - context: ModelContext for fetching and saving.
    static func pushLessonsWithAbsentStudents(in days: [Date], calendar: Calendar, context: ModelContext) {
        guard !days.isEmpty else { return }
        let start = calendar.startOfDay(for: days.first!)
        let end = calendar.startOfDay(for: (days.last.map { calendar.date(byAdding: .day, value: 1, to: $0) } ?? nil) ?? days.first!)
        // Fetch scheduled, un-given lessons within range
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { sl in
                sl.isPresented == false && sl.givenAt == nil && sl.scheduledFor != nil && sl.scheduledFor! >= start && sl.scheduledFor! < end
            }
        )
        let scheduled: [StudentLesson] = (try? context.fetch(descriptor)) ?? []

        // Fetch attendance records for the same range
        let attDescriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate { rec in rec.date >= start && rec.date < end }
        )
        let attendance: [AttendanceRecord] = (try? context.fetch(attDescriptor)) ?? []

        // Build lookup: (dayStart, studentID) -> status
        var attendanceMap: [Date: [UUID: AttendanceStatus]] = [:]
        for rec in attendance {
            let day = calendar.startOfDay(for: rec.date)
            var inner = attendanceMap[day] ?? [:]
            inner[rec.studentID] = rec.status
            attendanceMap[day] = inner
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
            let nextDay = SchoolCalendar.nextSchoolDay(after: day, using: context)
            let comps = calendar.dateComponents([.hour, .minute, .second], from: when)
            if let newDate = calendar.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: comps.second ?? 0, of: nextDay) {
                sl.setScheduledFor(newDate, using: AppCalendar.shared)
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Push all scheduled lessons forward by one school day, preserving their time-of-day.
    /// - Parameters:
    ///   - days: School days to consider (start-of-day dates). Only lessons scheduled on these days are moved.
    ///   - calendar: Calendar used to compute day boundaries and preserve time-of-day.
    ///   - context: ModelContext for fetching and saving.
    static func pushAllLessonsByOneDay(in days: [Date], calendar: Calendar, context: ModelContext) {
        guard !days.isEmpty else { return }
        let start = calendar.startOfDay(for: days.first!)
        let end = calendar.startOfDay(for: (days.last.map { calendar.date(byAdding: .day, value: 1, to: $0) } ?? nil) ?? days.first!)
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { sl in
                sl.isPresented == false && sl.givenAt == nil && sl.scheduledFor != nil && sl.scheduledFor! >= start && sl.scheduledFor! < end
            }
        )
        let scheduled: [StudentLesson] = (try? context.fetch(descriptor)) ?? []

        var changed = false
        for sl in scheduled {
            guard let when = sl.scheduledFor else { continue }
            let day = calendar.startOfDay(for: when)
            let nextDay = SchoolCalendar.nextSchoolDay(after: day, using: context)
            let comps = calendar.dateComponents([.hour, .minute, .second], from: when)
            if let newDate = calendar.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: comps.second ?? 0, of: nextDay) {
                sl.setScheduledFor(newDate, using: AppCalendar.shared)
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
