// StudentAreaProgressionViewModel.swift
// ViewModel for single student's progression through a area/sequence.

import Foundation
import OSLog
import CoreData

/// Builds the lesson timeline for one student in a area/sequence.
@Observable
final class StudentAreaProgressionViewModel {
    private static let logger = Logger.app_

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

        let fetchedLessons = fetchAllLessons(context: context)
        let fetchedPresentations = fetchPresentations(context: context)
        let fetchedWork = fetchAllWork(context: context)
        let fetchedCheckIns = fetchCheckIns(context: context)

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
        let studentWork = fetchedWork.filter { $0.studentID == studentIDStr }
        let studentCheckIns = fetchedCheckIns.filter { ci in
            if let workIDUUID = ci.workIDUUID {
                return studentWork.contains { $0.id == workIDUUID }
            }
            return false
        }

        // School day counting helper
        let calendar = AppCalendar.shared
        let today = calendar.startOfDay(for: Date())

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
            let scheduledPresentation = studentPresentations.first {
                $0.lessonID == lessonIDStr && $0.isScheduled
            }

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

                // Approximate school day age (weekdays only)
                let createdDay = calendar.startOfDay(for: work.assignedAt ?? Date())
                let weekdaysBetween = countWeekdays(from: createdDay, to: today, calendar: calendar)

                return WorkProgressItem(
                    id: work.id ?? UUID(),
                    work: work,
                    status: work.status,
                    kind: work.kind,
                    ageSchoolDays: weekdaysBetween,
                    lastCheckIn: lastCheckIn,
                    nextCheckIn: nextCheckIn
                )
            }

            // Determine status
            let status: LessonNodeStatus
            if presentation != nil {
                let allComplete = !lessonWork.isEmpty && lessonWork.allSatisfy { $0.status == .complete }
                let hasReview = lessonWork.contains { $0.status == .review }
                let hasActive = lessonWork.contains { $0.status != .complete }

                if allComplete {
                    status = .completed
                    completed += 1
                } else if hasReview {
                    status = .reviewing
                } else if hasActive && !lessonWork.isEmpty {
                    status = .practicing
                } else {
                    status = .presented
                }
            } else if let scheduled = scheduledPresentation, let date = scheduled.scheduledFor {
                status = .scheduled(date)
            } else {
                status = .notStarted
            }

            // Determine if this is the "next" lesson
            let isNext: Bool
            if !foundNext && presentation == nil && scheduledPresentation == nil {
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

    func scheduleNextLesson(after lesson: CDLesson, context: NSManagedObjectContext) {
        guard let student else { return }
        guard let nextLesson = PlanNextLessonService.findNextLesson(after: lesson, in: allLessons) else { return }
        guard let studentID = student.id else { return }
        PlanNextLessonService.planLesson(
            nextLesson,
            forStudents: [studentID],
            allStudents: [student],
            allLessons: allLessons,
            existingLessonAssignments: allPresentations,
            context: context
        )
        context.safeSave()
    }

    // MARK: - Helpers

    private func countWeekdays(from start: Date, to end: Date, calendar: Calendar) -> Int {
        guard start < end else { return 0 }
        let totalDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        guard totalDays > 0 else { return 0 }
        let fullWeeks = totalDays / 7
        let remainingDays = totalDays % 7
        var weekdays = fullWeeks * 5
        let startWeekday = calendar.component(.weekday, from: start) // 1=Sun, 7=Sat
        for i in 0..<remainingDays {
            let dayOfWeek = (startWeekday - 1 + i) % 7 + 1
            if dayOfWeek != 1 && dayOfWeek != 7 {
                weekdays += 1
            }
        }
        return weekdays
    }

    // MARK: - Fetching

    private func fetchAllLessons(context: NSManagedObjectContext) -> [CDLesson] {
        let descriptor: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
        descriptor.sortDescriptors = [
                NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
                NSSortDescriptor(keyPath: \CDLesson.sequence, ascending: true),
                NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true)
            ]
        return context.safeFetch(descriptor)
    }

    private func fetchPresentations(context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let descriptor = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        return context.safeFetch(descriptor)
    }

    private func fetchAllWork(context: NSManagedObjectContext) -> [CDWorkModel] {
        let descriptor = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        return context.safeFetch(descriptor)
    }

    private func fetchCheckIns(context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        let descriptor = NSFetchRequest<CDWorkCheckIn>(entityName: "WorkCheckIn")
        return context.safeFetch(descriptor)
    }
}
