// StudentAreaProgressionViewModel.swift
// ViewModel for single student's progression through a area/sequence.

import Foundation
import OSLog
import CoreData

/// Builds the lesson timeline for one student in a area/sequence.
@Observable
final class StudentAreaProgressionViewModel {
    private(set) var nodes: [LessonProgressionNode] = []
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var isLoading = false

    private var student: CDStudent?
    private var allLessons: [CDLesson] = []
    private var allPresentations: [CDLessonAssignment] = []

    // MARK: - Configuration

    // swiftlint:disable:next function_body_length
    func configure(for student: CDStudent, area: String, sequence: String, context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        // Lessons that could be in this area/sequence — a store-side superset
        // of the trimmed match below, which is also what the next-lesson
        // planner searches — and the presentations of any of them.
        let fetchedLessons = fetchLessons(area: area, sequence: sequence, context: context)
        let fetchedPresentations = fetchPresentations(
            lessonIDs: fetchedLessons.compactMap { $0.id?.uuidString }, context: context
        )

        allLessons = fetchedLessons
        allPresentations = fetchedPresentations
        self.student = student

        // Lessons in this sequence sorted by orderInSequence
        let groupLessons = fetchedLessons
            .filter { $0.area.trimmed() == area && $0.sequence.trimmed() == sequence }
            .sorted { $0.orderInSequence < $1.orderInSequence }

        totalCount = groupLessons.count

        // Her presentations, the work that counts as hers (shared project work
        // included), her mastery marks and her year plan in this sequence, each
        // lesson's rung by the Checklist's rule (`StudentLessonRecords`).
        let lessonIDs = groupLessons.map { $0.id?.uuidString ?? "" }
        let states = StudentLessonRecords(
            studentID: student.id ?? UUID(), lessonIDs: lessonIDs, presentations: fetchedPresentations,
            context: context
        ).states(lessonIDs: lessonIDs)
        let studentWork = states.flatMap(\.work)
        let studentCheckIns = fetchCheckIns(workIDs: studentWork.compactMap { $0.id?.uuidString }, context: context)

        let today = AppCalendar.startOfDay(Date())

        var completed = 0
        var result: [LessonProgressionNode] = []

        for (lesson, state) in zip(groupLessons, states) {
            // Build work progress items
            let workItems: [WorkProgressItem] = state.work.map { work in
                let workCheckIns = studentCheckIns.filter { $0.workIDUUID != nil && $0.workIDUUID == work.id }
                let lastCheckIn = workCheckIns
                    .filter { $0.status == .completed }
                    .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
                let nextCheckIn = workCheckIns
                    .filter(\.isScheduled)
                    .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }

                return WorkProgressItem(
                    id: work.id ?? UUID(),
                    work: work,
                    status: work.status,
                    kind: work.kind,
                    ageSchoolDays: Self.schoolDaysOpen(work, today: today, context: context),
                    lastCheckIn: lastCheckIn,
                    nextCheckIn: nextCheckIn
                )
            }

            if state.status == .mastered { completed += 1 }

            result.append(LessonProgressionNode(
                id: lesson.id ?? UUID(),
                lesson: lesson,
                orderInSequence: Int(lesson.orderInSequence),
                status: state.status,
                presentedAt: state.given?.presentedAt,
                presentationID: state.given?.id,
                activeWork: workItems,
                // The "next" lesson: the first not given, planned, practiced or mastered.
                isNext: state.isNext
            ))
        }

        nodes = result
        completedCount = completed
    }

    // MARK: - Actions

    /// Whether the timeline offers Plan Lesson: only for a child in the class.
    var canPlanLessons: Bool {
        student?.isEnrolled ?? false
    }

    /// Plans `lesson` itself for the child, as an inbox draft. It used to plan the
    /// lesson *after* the one tapped, and nothing on the last lesson (bug hunt
    /// 2026-10-10, P2 #35). The draft then shows the row as Planned.
    ///
    /// A child who has left the class gets no new plan (bug hunt 2026-11-03 #32):
    /// the timeline doesn't offer Plan Lesson for her (`canPlanLessons`), and if it
    /// is reached anyway this returns what to tell the guide, the message new work
    /// gets (`WorkRepository.requireEnrolled`). Nil when the lesson was planned.
    @discardableResult
    func planLesson(_ lesson: CDLesson, context: NSManagedObjectContext) -> String? {
        guard let student, let studentID = student.id else { return nil }
        do {
            try WorkRepository(context: context).requireEnrolled(studentID)
        } catch {
            return AppErrorMessages.userMessage(for: error)
        }
        PlanNextLessonService.planLesson(
            lesson,
            forStudents: [studentID],
            allStudents: [student],
            allLessons: allLessons,
            existingLessonAssignments: allPresentations,
            context: context
        )
        context.safeSave()
        return nil
    }

    // MARK: - Helpers

    /// School days the work has been open: from when it was assigned to today, or to
    /// the day it closed. Holidays and days off don't count (the school calendar);
    /// it used to count every weekday and keep counting after the work was closed.
    static func schoolDaysOpen(_ work: CDWorkModel, today: Date, context: NSManagedObjectContext) -> Int {
        let start = work.assignedAt ?? work.createdAt ?? today
        let end = work.status.isClosed ? (work.completedAt ?? today) : today
        return SchoolCalendarService.shared.schoolDaysBetween(start: start, end: min(end, today), using: context)
    }

    // MARK: - Fetching

    /// Lessons that could belong to `area` / `sequence` (see
    /// `SequenceStandingLoader.couldEqualPredicate`), in curriculum order.
    private func fetchLessons(area: String, sequence: String, context: NSManagedObjectContext) -> [CDLesson] {
        let descriptor = CDFetchRequest(CDLesson.self)
        descriptor.predicate = SequenceStandingLoader.couldEqualPredicate(area: area, sequence: sequence)
        descriptor.sortDescriptors = CDLesson.sortByCurriculumOrder
        return context.safeFetch(descriptor)
    }

    /// Presentations of any of `lessonIDs`, matched the way `lessonIDUUID`
    /// links them (case-insensitively), in store order.
    private func fetchPresentations(lessonIDs: [String], context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let descriptor = CDFetchRequest(CDLessonAssignment.self)
        descriptor.predicate = NSPredicate(format: "lessonID IN[c] %@", lessonIDs)
        return context.safeFetch(descriptor)
    }

    /// Check-ins whose `workID` parses to one of `workIDs`.
    private func fetchCheckIns(workIDs: [String], context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        let descriptor = CDFetchRequest(CDWorkCheckIn.self)
        descriptor.predicate = NSPredicate(format: "workID IN[c] %@", workIDs)
        return context.safeFetch(descriptor)
    }
}
