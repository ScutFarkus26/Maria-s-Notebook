// FridayReviewViewModel.swift
// ViewModel for the Friday Review Ritual — loads week data and computes review sections.

import SwiftUI
import CoreData

@Observable @MainActor
final class FridayReviewViewModel {
    private(set) var weekSummary: WeekSummary?
    private(set) var unobservedStudents: [UnobservedStudent] = []
    private(set) var followUpItems: [FollowUpItem] = []
    private(set) var staleWorkItems: [StaleWorkItem] = []
    private(set) var mondayPriorities: [MondayPriority] = []
    private(set) var isLoading = false

    var levelFilter: LevelFilter = .all

    // MARK: - Load Data

    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        let (weekStart, weekEnd) = computeWeekRange()

        // Fetch all enrolled visible students
        let studentRequest = CDFetchRequest(CDStudent.self)
        studentRequest.predicate = NSPredicate(
            format: "enrollmentStatusRaw == %@",
            CDStudent.EnrollmentStatus.enrolled.rawValue
        )
        studentRequest.sortDescriptors = CDStudent.sortByName
        let allStudents = TestStudentsFilter.filterVisible(context.safeFetch(studentRequest))

        // Index students by ID
        var studentsByID: [UUID: CDStudent] = [:]
        for student in allStudents {
            if let sid = student.id { studentsByID[sid] = student }
        }

        // Fetch week's notes
        let noteRequest = CDFetchRequest(CDNote.self)
        noteRequest.predicate = NSPredicate(
            format: "createdAt >= %@ AND createdAt <= %@",
            weekStart as NSDate, weekEnd as NSDate
        )
        let weekNotes = context.safeFetch(noteRequest)

        // Fetch week's presented assignments
        let assignmentRequest = CDFetchRequest(CDLessonAssignment.self)
        assignmentRequest.predicate = NSPredicate(
            format: "stateRaw == %@ AND presentedAt >= %@ AND presentedAt <= %@",
            LessonAssignmentState.presented.rawValue,
            weekStart as NSDate, weekEnd as NSDate
        )
        let weekAssignments = context.safeFetch(assignmentRequest)

        // Fetch week's completed work
        let completedWorkRequest = CDFetchRequest(CDWorkModel.self)
        completedWorkRequest.predicate = NSPredicate(
            format: "completedAt >= %@ AND completedAt <= %@",
            weekStart as NSDate, weekEnd as NSDate
        )
        let completedWork = context.safeFetch(completedWorkRequest)

        // Build week summary
        weekSummary = WeekSummary(
            presentationsGiven: weekAssignments.count,
            notesRecorded: weekNotes.count,
            workCompleted: completedWork.count,
            weekStart: weekStart,
            weekEnd: weekEnd
        )

        // Build observation map (student ID → notes)
        let observationMap = buildStudentObservationMap(from: weekNotes)

        // Find unobserved students
        let filteredStudents = filterByLevel(allStudents)
        unobservedStudents = filteredStudents.compactMap { student in
            guard let sid = student.id else { return nil }
            guard observationMap[sid] == nil else { return nil }

            // Optionally compute days since last note ever
            let daysSince = computeDaysSinceLastNote(
                studentID: sid,
                context: context
            )

            return UnobservedStudent(
                id: sid,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname,
                level: student.level,
                daysSinceLastNote: daysSince
            )
        }.sorted { ($0.daysSinceLastNote ?? Int.max) > ($1.daysSinceLastNote ?? Int.max) }

        // Build follow-up items
        buildFollowUpItems(context: context, studentsByID: studentsByID)

        // Build stale work items
        buildStaleWorkItems(context: context, studentsByID: studentsByID)

        // Generate Monday priorities
        buildMondayPriorities()
    }

    // MARK: - Helpers

    private func computeWeekRange() -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()

        // Find this week's Monday
        var weekStart = now
        while calendar.component(.weekday, from: weekStart) != 2 {
            weekStart = calendar.date(byAdding: .day, value: -1, to: weekStart) ?? weekStart
        }
        weekStart = calendar.startOfDay(for: weekStart)

        // Week end is end of today (or Friday if today is after Friday)
        let dayOfWeek = calendar.component(.weekday, from: now)
        let endDay: Date
        if dayOfWeek >= 7 || dayOfWeek == 1 {
            // Weekend — use Friday
            var friday = now
            while calendar.component(.weekday, from: friday) != 6 {
                friday = calendar.date(byAdding: .day, value: -1, to: friday) ?? friday
            }
            endDay = friday
        } else {
            endDay = now
        }
        let weekEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay) ?? endDay

        return (weekStart, weekEnd)
    }

    private func buildStudentObservationMap(from notes: [CDNote]) -> [UUID: [CDNote]] {
        var map: [UUID: [CDNote]] = [:]
        for note in notes {
            switch note.scope {
            case .all:
                break // All-scope notes don't count for per-student observation
            case .student(let studentID):
                map[studentID, default: []].append(note)
            case .students(let studentIDs):
                for studentID in studentIDs {
                    map[studentID, default: []].append(note)
                }
            }
        }
        return map
    }

    private func computeDaysSinceLastNote(studentID: UUID, context: NSManagedObjectContext) -> Int? {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "searchIndexStudentID == %@", studentID as CVarArg
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)]
        request.fetchLimit = 1
        guard let lastNote = context.safeFetch(request).first,
              let createdAt = lastNote.createdAt else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day
    }

    private func buildFollowUpItems(context: NSManagedObjectContext, studentsByID: [UUID: CDStudent]) {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "stateRaw == %@ AND (needsPractice == YES OR needsAnotherPresentation == YES)",
            LessonAssignmentState.presented.rawValue
        )
        let assignments = context.safeFetch(request)

        // Fetch all active/review work to check for follow-ups
        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = NSPredicate(
            format: "statusRaw IN %@",
            [WorkStatus.active.rawValue, WorkStatus.review.rawValue]
        )
        let activeWork = context.safeFetch(workRequest)
        let workByLessonID = Dictionary(grouping: activeWork) { $0.lessonID }

        // Fetch lessons for titles
        let lessonRequest = CDFetchRequest(CDLesson.self)
        let allLessons = context.safeFetch(lessonRequest)
        let lessonsByID: [String: CDLesson] = Dictionary(
            uniqueKeysWithValues: allLessons.compactMap { lesson in
                guard let lid = lesson.id else { return nil }
                return (lid.uuidString, lesson)
            }
        )

        followUpItems = assignments.compactMap { assignment in
            guard let aid = assignment.id else { return nil }

            // Check if follow-up work already exists
            let hasFollowUp = workByLessonID[assignment.lessonID]?.isEmpty == false
            guard !hasFollowUp else { return nil }

            let lessonTitle = lessonsByID[assignment.lessonID]?.name ?? "Unknown Lesson"
            let studentNames = assignment.studentIDs.compactMap { idStr -> String? in
                guard let uuid = UUID(uuidString: idStr),
                      let student = studentsByID[uuid] else { return nil }
                return StudentFormatter.displayName(for: student)
            }

            return FollowUpItem(
                id: aid,
                lessonTitle: lessonTitle,
                studentNames: studentNames,
                presentedAt: assignment.presentedAt ?? Date(),
                needsPractice: assignment.needsPractice,
                needsAnotherPresentation: assignment.needsAnotherPresentation
            )
        }.sorted { ($0.presentedAt) < ($1.presentedAt) }
    }

    private func buildStaleWorkItems(context: NSManagedObjectContext, studentsByID: [UUID: CDStudent]) {
        let staleThreshold = Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()

        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "(statusRaw == %@ OR statusRaw == %@) AND (lastTouchedAt < %@ OR (lastTouchedAt == nil AND createdAt < %@))",
            WorkStatus.active.rawValue, WorkStatus.review.rawValue,
            staleThreshold as NSDate, staleThreshold as NSDate
        )
        let staleWork = context.safeFetch(request)

        staleWorkItems = staleWork.compactMap { work in
            guard let wid = work.id else { return nil }
            let touchDate = work.lastTouchedAt ?? work.createdAt
            let daysSince: Int
            if let touch = touchDate {
                daysSince = Calendar.current.dateComponents([.day], from: touch, to: Date()).day ?? 0
            } else {
                daysSince = 99
            }

            let studentName: String
            if let uuid = UUID(uuidString: work.studentID),
               let student = studentsByID[uuid] {
                studentName = StudentFormatter.displayName(for: student)
            } else {
                studentName = "Unknown"
            }

            return StaleWorkItem(
                id: wid,
                title: work.title,
                studentName: studentName,
                status: work.status,
                lastTouchedAt: touchDate,
                daysSinceTouch: daysSince
            )
        }.sorted { $0.daysSinceTouch > $1.daysSinceTouch }
    }

    private func buildMondayPriorities() {
        var priorities: [MondayPriority] = []

        // Top 3 unobserved students
        for student in unobservedStudents.prefix(3) {
            let detail: String
            if let days = student.daysSinceLastNote {
                detail = "\(days) days since last observation"
            } else {
                detail = "Never observed"
            }
            priorities.append(MondayPriority(
                id: "unobserved-\(student.id)",
                priorityType: .unobserved,
                title: "Observe \(student.displayName)",
                detail: detail,
                urgency: 0
            ))
        }

        // Stale work items (7+ days)
        for work in staleWorkItems.filter({ $0.daysSinceTouch >= 7 }).prefix(3) {
            priorities.append(MondayPriority(
                id: "stale-\(work.id)",
                priorityType: .staleWork,
                title: "Check on \(work.title)",
                detail: "\(work.studentName) — \(work.daysSinceTouch) days untouched",
                urgency: 1
            ))
        }

        // Follow-up items
        for item in followUpItems.prefix(4) {
            let flags = [
                item.needsPractice ? "practice" : nil,
                item.needsAnotherPresentation ? "re-present" : nil
            ].compactMap { $0 }.joined(separator: ", ")
            priorities.append(MondayPriority(
                id: "followup-\(item.id)",
                priorityType: .followUp,
                title: item.lessonTitle,
                detail: "\(item.studentNames.joined(separator: ", ")) — needs \(flags)",
                urgency: 2
            ))
        }

        mondayPriorities = priorities.sorted { $0.urgency < $1.urgency }
    }

    private func filterByLevel(_ students: [CDStudent]) -> [CDStudent] {
        guard levelFilter != .all else { return students }
        return students.filter { levelFilter.matches($0.level) }
    }
}
