//
//  PresentationRepository.swift
//  Maria's Notebook
//
//  Repository for CDLessonAssignment (Presentation) CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct PresentationRepository: SavingRepository {
    typealias Model = CDLessonAssignment

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDLessonAssignment by ID
    func fetchLessonAssignment(id: UUID) -> CDLessonAssignment? {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch multiple LessonAssignments with optional filtering and sorting
    func fetchLessonAssignments(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "createdAt", ascending: false)]
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        return context.safeFetch(request)
    }

    /// Fetch LessonAssignments for a specific lesson
    func fetchLessonAssignments(forLessonID lessonID: UUID) -> [CDLessonAssignment] {
        fetchLessonAssignments(predicate: NSPredicate(format: "lessonID == %@", lessonID.uuidString))
    }

    /// Fetch inbox items (draft or scheduled but not yet presented)
    func fetchInboxItems() -> [CDLessonAssignment] {
        fetchLessonAssignments(predicate: NSPredicate(format: "stateRaw == %@ OR stateRaw == %@", "draft", "scheduled"))
    }

    /// Fetch scheduled LessonAssignments for a date range
    func fetchScheduled(from startDate: Date, to endDate: Date) -> [CDLessonAssignment] {
        fetchLessonAssignments(
            predicate: NSPredicate(format: "scheduledForDay >= %@ AND scheduledForDay < %@", startDate as NSDate, endDate as NSDate),
            sortBy: [NSSortDescriptor(key: "scheduledForDay", ascending: true)]
        )
    }

    /// Fetch active (not yet presented) LessonAssignments
    func fetchActiveAssignments() -> [CDLessonAssignment] {
        fetchLessonAssignments(predicate: NSPredicate(format: "stateRaw != %@", "presented"))
    }

    // MARK: - Create (using PresentationFactory)

    /// Create a draft CDLessonAssignment
    @discardableResult
    func createDraft(
        lessonID: UUID,
        studentIDs: [UUID]
    ) -> CDLessonAssignment {
        PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: studentIDs, context: context)
    }

    /// Create a draft CDLessonAssignment with relationship objects
    @discardableResult
    func createDraft(
        lesson: CDLesson,
        students: [CDStudent]
    ) -> CDLessonAssignment {
        PresentationFactory.makeDraft(lesson: lesson, students: students, context: context)
    }

    /// Create a scheduled CDLessonAssignment
    @discardableResult
    func createScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date
    ) -> CDLessonAssignment {
        PresentationFactory.makeScheduled(lessonID: lessonID, studentIDs: studentIDs, scheduledFor: scheduledFor, context: context)
    }

    /// Create a scheduled CDLessonAssignment with relationship objects
    @discardableResult
    func createScheduled(
        lesson: CDLesson,
        students: [CDStudent],
        scheduledFor: Date
    ) -> CDLessonAssignment {
        PresentationFactory.makeScheduled(lesson: lesson, students: students, scheduledFor: scheduledFor, context: context)
    }

    /// Create a presented CDLessonAssignment
    @discardableResult
    func createPresented(
        lessonID: UUID,
        studentIDs: [UUID],
        presentedAt: Date = Date()
    ) -> CDLessonAssignment {
        PresentationFactory.makePresented(lessonID: lessonID, studentIDs: studentIDs, presentedAt: presentedAt, context: context)
    }

    /// Create a presented CDLessonAssignment with relationship objects
    @discardableResult
    func createPresented(
        lesson: CDLesson,
        students: [CDStudent],
        presentedAt: Date = Date()
    ) -> CDLessonAssignment {
        PresentationFactory.makePresented(lesson: lesson, students: students, presentedAt: presentedAt, context: context)
    }

    // MARK: - Update

    /// Schedule a CDLessonAssignment
    @discardableResult
    func schedule(id: UUID, for date: Date, using calendar: Calendar = AppCalendar.shared) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.schedule(for: date, using: calendar)
        return true
    }

    /// Unschedule a CDLessonAssignment (move back to draft)
    @discardableResult
    func unschedule(id: UUID) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.unschedule()
        return true
    }

    /// Mark a CDLessonAssignment as presented
    @discardableResult
    func markPresented(id: UUID, presentedAt: Date = Date()) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.markPresented(at: presentedAt)
        return true
    }

    /// Update notes for a CDLessonAssignment
    @discardableResult
    func updateNotes(id: UUID, notes: String) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.notes = notes
        la.modifiedAt = Date()
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
        guard let la = fetchLessonAssignment(id: id) else { return false }

        if let needsPractice { la.needsPractice = needsPractice }
        if let needsAnotherPresentation { la.needsAnotherPresentation = needsAnotherPresentation }
        if let followUpWork { la.followUpWork = followUpWork }

        la.modifiedAt = Date()
        return true
    }

    // MARK: - Delete

    /// Delete a CDLessonAssignment by ID
    func deleteLessonAssignment(id: UUID) throws {
        guard let la = fetchLessonAssignment(id: id) else { return }
        context.delete(la)
        try context.save()
    }
}
