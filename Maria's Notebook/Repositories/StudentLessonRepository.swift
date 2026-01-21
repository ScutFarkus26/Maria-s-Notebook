//
//  StudentLessonRepository.swift
//  Maria's Notebook
//
//  Repository for StudentLesson entity CRUD operations.
//  Integrates with StudentLessonFactory for entity creation.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import SwiftData

@MainActor
struct StudentLessonRepository: SavingRepository {
    typealias Model = StudentLesson

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a StudentLesson by ID
    func fetchStudentLesson(id: UUID) -> StudentLesson? {
        let descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Fetch multiple StudentLessons with optional filtering and sorting
    /// - Parameters:
    ///   - predicate: Optional predicate to filter. If nil, fetches all.
    ///   - sortBy: Optional sort descriptors. Defaults to sorting by createdAt descending.
    /// - Returns: Array of StudentLesson entities matching the criteria
    func fetchStudentLessons(
        predicate: Predicate<StudentLesson>? = nil,
        sortBy: [SortDescriptor<StudentLesson>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [StudentLesson] {
        var descriptor = FetchDescriptor<StudentLesson>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch StudentLessons for a specific lesson
    func fetchStudentLessons(forLessonID lessonID: UUID) -> [StudentLesson] {
        let lessonIDString = lessonID.uuidString
        let predicate = #Predicate<StudentLesson> { $0.lessonID == lessonIDString }
        return fetchStudentLessons(predicate: predicate)
    }

    /// Fetch unscheduled StudentLessons (inbox items)
    func fetchInboxItems() -> [StudentLesson] {
        let predicate = #Predicate<StudentLesson> { sl in
            sl.scheduledFor == nil && !sl.isPresented && sl.givenAt == nil
        }
        return fetchStudentLessons(predicate: predicate)
    }

    /// Fetch scheduled StudentLessons for a date range
    func fetchScheduled(from startDate: Date, to endDate: Date) -> [StudentLesson] {
        let predicate = #Predicate<StudentLesson> { sl in
            sl.scheduledForDay >= startDate && sl.scheduledForDay < endDate
        }
        return fetchStudentLessons(
            predicate: predicate,
            sortBy: [SortDescriptor(\.scheduledForDay)]
        )
    }

    // MARK: - Create (using StudentLessonFactory)

    /// Create an unscheduled StudentLesson (inbox item)
    @discardableResult
    func createUnscheduled(
        lessonID: UUID,
        studentIDs: [UUID]
    ) -> StudentLesson {
        let sl = StudentLessonFactory.makeUnscheduled(
            lessonID: lessonID,
            studentIDs: studentIDs
        )
        context.insert(sl)
        return sl
    }

    /// Create an unscheduled StudentLesson with relationship objects
    @discardableResult
    func createUnscheduled(
        lesson: Lesson,
        students: [Student]
    ) -> StudentLesson {
        let sl = StudentLessonFactory.makeUnscheduled(
            lesson: lesson,
            students: students
        )
        context.insert(sl)
        return sl
    }

    /// Create a scheduled StudentLesson
    @discardableResult
    func createScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date
    ) -> StudentLesson {
        let sl = StudentLessonFactory.makeScheduled(
            lessonID: lessonID,
            studentIDs: studentIDs,
            scheduledFor: scheduledFor
        )
        context.insert(sl)
        return sl
    }

    /// Create a scheduled StudentLesson with relationship objects
    @discardableResult
    func createScheduled(
        lesson: Lesson,
        students: [Student],
        scheduledFor: Date
    ) -> StudentLesson {
        let sl = StudentLessonFactory.makeScheduled(
            lesson: lesson,
            students: students,
            scheduledFor: scheduledFor
        )
        context.insert(sl)
        return sl
    }

    /// Create a presented/given StudentLesson
    @discardableResult
    func createPresented(
        lessonID: UUID,
        studentIDs: [UUID],
        givenAt: Date = Date()
    ) -> StudentLesson {
        let sl = StudentLessonFactory.makePresented(
            lessonID: lessonID,
            studentIDs: studentIDs,
            givenAt: givenAt
        )
        context.insert(sl)
        return sl
    }

    /// Create a presented StudentLesson with relationship objects
    @discardableResult
    func createPresented(
        lesson: Lesson,
        students: [Student],
        givenAt: Date = Date()
    ) -> StudentLesson {
        let sl = StudentLessonFactory.makePresented(
            lesson: lesson,
            students: students,
            givenAt: givenAt
        )
        context.insert(sl)
        return sl
    }

    // MARK: - Update

    /// Schedule a StudentLesson
    @discardableResult
    func schedule(id: UUID, for date: Date, using calendar: Calendar = .current) -> Bool {
        guard let sl = fetchStudentLesson(id: id) else { return false }
        sl.setScheduledFor(date, using: calendar)
        return true
    }

    /// Unschedule a StudentLesson (move back to inbox)
    @discardableResult
    func unschedule(id: UUID) -> Bool {
        guard let sl = fetchStudentLesson(id: id) else { return false }
        sl.setScheduledFor(nil, using: .current)
        return true
    }

    /// Mark a StudentLesson as presented/given
    @discardableResult
    func markPresented(id: UUID, givenAt: Date = Date()) -> Bool {
        guard let sl = fetchStudentLesson(id: id) else { return false }
        sl.isPresented = true
        sl.givenAt = givenAt
        return true
    }

    /// Update notes for a StudentLesson
    @discardableResult
    func updateNotes(id: UUID, notes: String) -> Bool {
        guard let sl = fetchStudentLesson(id: id) else { return false }
        sl.notes = notes
        return true
    }

    /// Update follow-up flags
    @discardableResult
    func updateFollowUp(
        id: UUID,
        needsPractice: Bool? = nil,
        needsAnotherPresentation: Bool? = nil,
        followUpWork: String? = nil
    ) -> Bool {
        guard let sl = fetchStudentLesson(id: id) else { return false }

        if let needsPractice = needsPractice {
            sl.needsPractice = needsPractice
        }
        if let needsAnotherPresentation = needsAnotherPresentation {
            sl.needsAnotherPresentation = needsAnotherPresentation
        }
        if let followUpWork = followUpWork {
            sl.followUpWork = followUpWork
        }

        return true
    }

    // MARK: - Delete

    /// Delete a StudentLesson by ID
    func deleteStudentLesson(id: UUID) throws {
        guard let sl = fetchStudentLesson(id: id) else { return }
        context.delete(sl)
        try context.save()
    }
}
