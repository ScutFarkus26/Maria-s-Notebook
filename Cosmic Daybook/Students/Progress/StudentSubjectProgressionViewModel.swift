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

        let studentIDStr = student.id?.uuidString ?? ""

        // Lessons in this sequence sorted by orderInSequence
        let groupLessons = fetchedLessons
            .filter { $0.area.trimmed() == area && $0.sequence.trimmed() == sequence }
            .sorted { $0.orderInSequence < $1.orderInSequence }

        totalCount = groupLessons.count

        // CDStudent's presentations and work in this sequence
        let studentPresentations = fetchedPresentations.filter { $0.studentIDs.contains(studentIDStr) }
        let studentWork = fetchWork(
            studentID: studentIDStr, lessonIDs: groupLessons.map { $0.id?.uuidString ?? "" }, context: context
        )
        let studentCheckIns = fetchCheckIns(workIDs: studentWork.compactMap { $0.id?.uuidString }, context: context)
        // Mastery is the mark on the lesson, as on the class checklist — not closed work.
        let masteredLessonIDs = Set(
            PresentationRecordIndex.masteryMarks(
                lessonIDs: Set(groupLessons.compactMap { $0.id?.uuidString }), in: context
            )
            .filter { $0.value.contains(studentIDStr) }
            .keys
        )

        let today = AppCalendar.startOfDay(Date())

        var completed = 0
        var foundNext = false
        var result: [LessonProgressionNode] = []

        for lesson in groupLessons {
            let lessonIDStr = lesson.id?.uuidString ?? ""

            // Find matching presentation. "Previously Presented" records are undated
            // (state == .presented, presentedAt == nil), so match on state as well —
            // otherwise historical lessons show Not Started and get re-suggested as next.
            let presentation = studentPresentations.first {
                $0.lessonID == lessonIDStr && ($0.isPresented || $0.presentedAt != nil)
            }
            // Planned and not yet given: on a day, or a draft waiting in the inbox.
            let plannedPresentations = studentPresentations.filter {
                $0.lessonID == lessonIDStr && !$0.isPresented && $0.presentedAt == nil
            }
            let isMastered = masteredLessonIDs.contains(lessonIDStr)

            // Find work items for this lesson
            let lessonWork = studentWork.filter { $0.lessonID == lessonIDStr }

            // Build work progress items
            let workItems: [WorkProgressItem] = lessonWork.map { work in
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

            let status = LessonNodeStatus.resolve(
                isPresented: presentation != nil,
                scheduledFor: plannedPresentations.compactMap(\.scheduledFor).min(),
                isPlanned: !plannedPresentations.isEmpty,
                isMastered: isMastered,
                workStatuses: lessonWork.map(\.status)
            )
            if status == .mastered { completed += 1 }

            // The "next" lesson: the first not given, not planned and not mastered.
            let isNext: Bool
            if !foundNext && status == .notStarted && plannedPresentations.isEmpty {
                isNext = true
                foundNext = true
            } else {
                isNext = false
            }

            result.append(LessonProgressionNode(
                id: lesson.id ?? UUID(),
                lesson: lesson,
                orderInSequence: Int(lesson.orderInSequence),
                status: status,
                presentedAt: presentation?.presentedAt,
                presentationID: presentation?.id,
                activeWork: workItems,
                isNext: isNext
            ))
        }

        nodes = result
        completedCount = completed
    }

    // MARK: - Actions

    /// Plans `lesson` itself for the child, as an inbox draft. It used to plan the
    /// lesson *after* the one tapped, and nothing on the last lesson (bug hunt
    /// 2026-10-10, P2 #35). The draft then shows the row as Planned.
    func planLesson(_ lesson: CDLesson, context: NSManagedObjectContext) {
        guard let student, let studentID = student.id else { return }
        PlanNextLessonService.planLesson(
            lesson,
            forStudents: [studentID],
            allStudents: [student],
            allLessons: allLessons,
            existingLessonAssignments: allPresentations,
            context: context
        )
        context.safeSave()
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
    /// `SequenceTrackService.couldEqualPredicate`), in curriculum order.
    private func fetchLessons(area: String, sequence: String, context: NSManagedObjectContext) -> [CDLesson] {
        let descriptor = CDFetchRequest(CDLesson.self)
        descriptor.predicate = SequenceTrackService.couldEqualPredicate(area: area, sequence: sequence)
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

    /// The student's work on any of `lessonIDs` (exact string matches).
    private func fetchWork(studentID: String, lessonIDs: [String], context: NSManagedObjectContext) -> [CDWorkModel] {
        let descriptor = CDFetchRequest(CDWorkModel.self)
        descriptor.predicate = NSPredicate(format: "studentID == %@ AND lessonID IN %@", studentID, lessonIDs)
        return context.safeFetch(descriptor)
    }

    /// Check-ins whose `workID` parses to one of `workIDs`.
    private func fetchCheckIns(workIDs: [String], context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        let descriptor = CDFetchRequest(CDWorkCheckIn.self)
        descriptor.predicate = NSPredicate(format: "workID IN[c] %@", workIDs)
        return context.safeFetch(descriptor)
    }
}
