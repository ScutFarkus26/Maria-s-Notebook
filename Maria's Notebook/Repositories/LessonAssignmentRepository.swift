//
//  LessonAssignmentRepository.swift
//  Maria's Notebook
//
//  Repository for LessonAssignment entity CRUD operations.
//  Mirrors the API of StudentLessonRepository for easy transition.
//  Part of Phase 4 of the StudentLesson + Presentation consolidation.
//

import Foundation
import SwiftData

@MainActor
struct LessonAssignmentRepository: SavingRepository {
    typealias Model = LessonAssignment

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch by ID

    /// Fetch a LessonAssignment by ID
    func fetch(id: UUID) -> LessonAssignment? {
        let descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Fetch a LessonAssignment by its migrated StudentLesson ID
    func fetchByStudentLessonID(_ studentLessonID: UUID) -> LessonAssignment? {
        let idString = studentLessonID.uuidString
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.migratedFromStudentLessonID == idString }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Fetch a LessonAssignment by its migrated Presentation ID
    func fetchByPresentationID(_ presentationID: UUID) -> LessonAssignment? {
        let idString = presentationID.uuidString
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.migratedFromPresentationID == idString }
        )
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Fetch Multiple

    /// Fetch multiple LessonAssignments with optional filtering and sorting
    func fetchAll(
        predicate: Predicate<LessonAssignment>? = nil,
        sortBy: [SortDescriptor<LessonAssignment>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [LessonAssignment] {
        var descriptor = FetchDescriptor<LessonAssignment>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch LessonAssignments for a specific lesson
    func fetchForLesson(id lessonID: UUID) -> [LessonAssignment] {
        let lessonIDString = lessonID.uuidString
        let predicate = #Predicate<LessonAssignment> { $0.lessonID == lessonIDString }
        return fetchAll(predicate: predicate)
    }

    /// Fetch LessonAssignments containing a specific student
    func fetchForStudent(id studentID: UUID) -> [LessonAssignment] {
        // Note: This requires fetching all and filtering in memory because
        // SwiftData predicates don't support array contains operations well.
        // For performance, consider adding a denormalized field if this is called frequently.
        let all = fetchAll()
        let studentIDString = studentID.uuidString
        return all.filter { $0.studentIDs.contains(studentIDString) }
    }

    // MARK: - Fetch by State

    /// Fetch draft LessonAssignments (inbox items - unscheduled, not presented)
    func fetchDrafts() -> [LessonAssignment] {
        let draftState = LessonAssignmentState.draft.rawValue
        let predicate = #Predicate<LessonAssignment> { $0.stateRaw == draftState }
        return fetchAll(predicate: predicate)
    }

    /// Fetch scheduled LessonAssignments
    func fetchScheduled() -> [LessonAssignment] {
        let scheduledState = LessonAssignmentState.scheduled.rawValue
        let predicate = #Predicate<LessonAssignment> { $0.stateRaw == scheduledState }
        return fetchAll(predicate: predicate, sortBy: [SortDescriptor(\.scheduledForDay)])
    }

    /// Fetch scheduled LessonAssignments for a date range
    func fetchScheduled(from startDate: Date, to endDate: Date) -> [LessonAssignment] {
        let scheduledState = LessonAssignmentState.scheduled.rawValue
        let predicate = #Predicate<LessonAssignment> { la in
            la.stateRaw == scheduledState &&
            la.scheduledForDay >= startDate &&
            la.scheduledForDay < endDate
        }
        return fetchAll(predicate: predicate, sortBy: [SortDescriptor(\.scheduledForDay)])
    }

    /// Fetch scheduled LessonAssignments for a specific day
    func fetchScheduled(for date: Date, using calendar: Calendar = AppCalendar.shared) -> [LessonAssignment] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return fetchScheduled(from: startOfDay, to: endOfDay)
    }

    /// Fetch presented LessonAssignments
    func fetchPresented() -> [LessonAssignment] {
        let presentedState = LessonAssignmentState.presented.rawValue
        let predicate = #Predicate<LessonAssignment> { $0.stateRaw == presentedState }
        return fetchAll(predicate: predicate, sortBy: [SortDescriptor(\.presentedAt, order: .reverse)])
    }

    /// Fetch presented LessonAssignments for a date range
    func fetchPresented(from startDate: Date, to endDate: Date) -> [LessonAssignment] {
        let presentedState = LessonAssignmentState.presented.rawValue
        let predicate = #Predicate<LessonAssignment> { la in
            la.stateRaw == presentedState &&
            la.presentedAt != nil &&
            la.presentedAt! >= startDate &&
            la.presentedAt! < endDate
        }
        return fetchAll(predicate: predicate, sortBy: [SortDescriptor(\.presentedAt, order: .reverse)])
    }

    /// Fetch active (not yet presented) LessonAssignments
    func fetchActive() -> [LessonAssignment] {
        let presentedState = LessonAssignmentState.presented.rawValue
        let predicate = #Predicate<LessonAssignment> { $0.stateRaw != presentedState }
        return fetchAll(predicate: predicate)
    }

    // MARK: - Create

    /// Create a draft LessonAssignment (inbox item)
    @discardableResult
    func createDraft(
        lessonID: UUID,
        studentIDs: [UUID],
        lesson: Lesson? = nil
    ) -> LessonAssignment {
        let la = LessonAssignment(
            state: .draft,
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: lesson
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
        let la = LessonAssignment(
            lesson: lesson,
            students: students,
            state: .draft
        )
        context.insert(la)
        return la
    }

    /// Create a scheduled LessonAssignment
    @discardableResult
    func createScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date,
        lesson: Lesson? = nil
    ) -> LessonAssignment {
        let la = LessonAssignment(
            state: .scheduled,
            scheduledFor: scheduledFor,
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: lesson
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
        let la = LessonAssignment(
            lesson: lesson,
            students: students,
            state: .scheduled,
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
        presentedAt: Date = Date(),
        lesson: Lesson? = nil
    ) -> LessonAssignment {
        let la = LessonAssignment(
            state: .presented,
            presentedAt: presentedAt,
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: lesson
        )
        // Snapshot lesson info if available
        if let lesson = lesson {
            la.lessonTitleSnapshot = lesson.name
            la.lessonSubheadingSnapshot = lesson.subheading
        }
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
        let la = LessonAssignment(
            lesson: lesson,
            students: students,
            state: .presented,
            scheduledFor: nil
        )
        la.markPresented(at: presentedAt)
        context.insert(la)
        return la
    }

    // MARK: - Update State

    /// Schedule a LessonAssignment
    @discardableResult
    func schedule(id: UUID, for date: Date, using calendar: Calendar = AppCalendar.shared) -> Bool {
        guard let la = fetch(id: id) else { return false }
        la.schedule(for: date, using: calendar)
        return true
    }

    /// Unschedule a LessonAssignment (move back to draft/inbox)
    @discardableResult
    func unschedule(id: UUID) -> Bool {
        guard let la = fetch(id: id) else { return false }
        la.unschedule()
        return true
    }

    /// Mark a LessonAssignment as presented
    @discardableResult
    func markPresented(id: UUID, at date: Date = Date()) -> Bool {
        guard let la = fetch(id: id) else { return false }
        la.markPresented(at: date)
        return true
    }

    // MARK: - Update Fields

    /// Update notes for a LessonAssignment
    @discardableResult
    func updateNotes(id: UUID, notes: String) -> Bool {
        guard let la = fetch(id: id) else { return false }
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
        guard let la = fetch(id: id) else { return false }

        if let needsPractice = needsPractice {
            la.needsPractice = needsPractice
        }
        if let needsAnotherPresentation = needsAnotherPresentation {
            la.needsAnotherPresentation = needsAnotherPresentation
        }
        if let followUpWork = followUpWork {
            la.followUpWork = followUpWork
        }
        la.modifiedAt = Date()

        return true
    }

    /// Update students for a LessonAssignment
    @discardableResult
    func updateStudents(id: UUID, studentIDs: [UUID]) -> Bool {
        guard let la = fetch(id: id) else { return false }
        la.studentIDs = studentIDs.map { $0.uuidString }
        la.updateDenormalizedKeys()
        la.modifiedAt = Date()
        return true
    }

    // MARK: - Delete

    /// Delete a LessonAssignment by ID
    func delete(id: UUID) throws {
        guard let la = fetch(id: id) else { return }
        context.delete(la)
        try context.save()
    }

    /// Delete a LessonAssignment
    func delete(_ assignment: LessonAssignment) throws {
        context.delete(assignment)
        try context.save()
    }
}

// MARK: - Convenience Extensions

extension LessonAssignmentRepository {
    /// Fetch count of LessonAssignments by state
    func count(state: LessonAssignmentState) -> Int {
        let stateRaw = state.rawValue
        let predicate = #Predicate<LessonAssignment> { $0.stateRaw == stateRaw }
        let descriptor = FetchDescriptor<LessonAssignment>(predicate: predicate)
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Fetch total count of all LessonAssignments
    func countAll() -> Int {
        let descriptor = FetchDescriptor<LessonAssignment>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Check if a lesson has been presented to specific students
    func hasBeenPresented(lessonID: UUID, studentIDs: [UUID]) -> Bool {
        let assignments = fetchForLesson(id: lessonID)
        let studentIDStrings = Set(studentIDs.map { $0.uuidString })

        for la in assignments where la.state == .presented {
            let laStudentIDs = Set(la.studentIDs)
            if laStudentIDs == studentIDStrings {
                return true
            }
        }
        return false
    }
}
