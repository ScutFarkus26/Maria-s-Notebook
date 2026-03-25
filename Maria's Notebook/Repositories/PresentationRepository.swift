//
//  PresentationRepository.swift
//  Maria's Notebook
//
//  Repository for LessonAssignment (Presentation) entity CRUD operations.
//  Repository for LessonAssignment (Presentation) CRUD operations.
//

import Foundation
import OSLog
import SwiftData

@MainActor
struct PresentationRepository: SavingRepository {
    typealias Model = LessonAssignment

    private static let logger = Logger.database

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a LessonAssignment by ID
    func fetchLessonAssignment(id: UUID) -> LessonAssignment? {
        var descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch multiple LessonAssignments with optional filtering and sorting
    /// - Parameters:
    ///   - predicate: Optional predicate to filter. If nil, fetches all.
    ///   - sortBy: Optional sort descriptors. Defaults to sorting by createdAt descending.
    /// - Returns: Array of LessonAssignment entities matching the criteria
    func fetchLessonAssignments(
        predicate: Predicate<LessonAssignment>? = nil,
        sortBy: [SortDescriptor<LessonAssignment>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [LessonAssignment] {
        var descriptor = FetchDescriptor<LessonAssignment>()
        if let predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    /// Fetch LessonAssignments for a specific lesson
    func fetchLessonAssignments(forLessonID lessonID: UUID) -> [LessonAssignment] {
        let lessonIDString = lessonID.uuidString
        let predicate = #Predicate<LessonAssignment> { $0.lessonID == lessonIDString }
        return fetchLessonAssignments(predicate: predicate)
    }

    /// Fetch inbox items (draft or scheduled but not yet presented)
    func fetchInboxItems() -> [LessonAssignment] {
        let predicate = #Predicate<LessonAssignment> { la in
            la.stateRaw == "draft" || la.stateRaw == "scheduled"
        }
        return fetchLessonAssignments(predicate: predicate)
    }

    /// Fetch scheduled LessonAssignments for a date range
    func fetchScheduled(from startDate: Date, to endDate: Date) -> [LessonAssignment] {
        let predicate = #Predicate<LessonAssignment> { la in
            la.scheduledForDay >= startDate && la.scheduledForDay < endDate
        }
        return fetchLessonAssignments(
            predicate: predicate,
            sortBy: [SortDescriptor(\.scheduledForDay)]
        )
    }

    /// Fetch active (not yet presented) LessonAssignments
    func fetchActiveAssignments() -> [LessonAssignment] {
        let predicate = #Predicate<LessonAssignment> { la in
            la.stateRaw != "presented"
        }
        return fetchLessonAssignments(predicate: predicate)
    }

    // MARK: - Create (using PresentationFactory)

    /// Create a draft LessonAssignment
    @discardableResult
    func createDraft(
        lessonID: UUID,
        studentIDs: [UUID]
    ) -> LessonAssignment {
        let la = PresentationFactory.makeDraft(
            lessonID: lessonID,
            studentIDs: studentIDs
        )
        context.insert(la)
        return la
    }

    /// Create a draft LessonAssignment with relationship objects
    @discardableResult
    func createDraft(
        lesson: Lesson,
        students: [Student]
    ) -> LessonAssignment {
        let la = PresentationFactory.makeDraft(
            lesson: lesson,
            students: students
        )
        context.insert(la)
        return la
    }

    /// Create a scheduled LessonAssignment
    @discardableResult
    func createScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date
    ) -> LessonAssignment {
        let la = PresentationFactory.makeScheduled(
            lessonID: lessonID,
            studentIDs: studentIDs,
            scheduledFor: scheduledFor
        )
        context.insert(la)
        return la
    }

    /// Create a scheduled LessonAssignment with relationship objects
    @discardableResult
    func createScheduled(
        lesson: Lesson,
        students: [Student],
        scheduledFor: Date
    ) -> LessonAssignment {
        let la = PresentationFactory.makeScheduled(
            lesson: lesson,
            students: students,
            scheduledFor: scheduledFor
        )
        context.insert(la)
        return la
    }

    /// Create a presented LessonAssignment
    @discardableResult
    func createPresented(
        lessonID: UUID,
        studentIDs: [UUID],
        presentedAt: Date = Date()
    ) -> LessonAssignment {
        let la = PresentationFactory.makePresented(
            lessonID: lessonID,
            studentIDs: studentIDs,
            presentedAt: presentedAt
        )
        context.insert(la)
        return la
    }

    /// Create a presented LessonAssignment with relationship objects
    @discardableResult
    func createPresented(
        lesson: Lesson,
        students: [Student],
        presentedAt: Date = Date()
    ) -> LessonAssignment {
        let la = PresentationFactory.makePresented(
            lesson: lesson,
            students: students,
            presentedAt: presentedAt
        )
        context.insert(la)
        return la
    }

    // MARK: - Update

    /// Schedule a LessonAssignment
    @discardableResult
    func schedule(id: UUID, for date: Date, using calendar: Calendar = AppCalendar.shared) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.schedule(for: date, using: calendar)
        return true
    }

    /// Unschedule a LessonAssignment (move back to draft)
    @discardableResult
    func unschedule(id: UUID) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.unschedule()
        return true
    }

    /// Mark a LessonAssignment as presented
    @discardableResult
    func markPresented(id: UUID, presentedAt: Date = Date()) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.markPresented(at: presentedAt)
        return true
    }

    /// Update notes for a LessonAssignment
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

        if let needsPractice {
            la.needsPractice = needsPractice
        }
        if let needsAnotherPresentation {
            la.needsAnotherPresentation = needsAnotherPresentation
        }
        if let followUpWork {
            la.followUpWork = followUpWork
        }

        la.modifiedAt = Date()
        return true
    }

    // MARK: - Delete

    /// Delete a LessonAssignment by ID
    func deleteLessonAssignment(id: UUID) throws {
        guard let la = fetchLessonAssignment(id: id) else { return }
        context.delete(la)
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error, privacy: .public)")
            throw error
        }
    }
}
