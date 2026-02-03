//
//  PresentationRepository.swift
//  Maria's Notebook
//
//  Repository for Presentation entity CRUD operations.
//

import Foundation
import SwiftData

@MainActor
struct PresentationRepository: SavingRepository {
    typealias Model = Presentation

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch by ID

    /// Fetch a Presentation by ID
    func fetch(id: UUID) -> Presentation? {
        var descriptor = FetchDescriptor<Presentation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Fetch a Presentation by its migrated StudentLesson ID
    func fetchByStudentLessonID(_ studentLessonID: UUID) -> Presentation? {
        let idString = studentLessonID.uuidString
        var descriptor = FetchDescriptor<Presentation>(
            predicate: #Predicate { $0.migratedFromStudentLessonID == idString }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Fetch a Presentation by its migrated old Presentation ID
    func fetchByOldPresentationID(_ presentationID: UUID) -> Presentation? {
        let idString = presentationID.uuidString
        var descriptor = FetchDescriptor<Presentation>(
            predicate: #Predicate { $0.migratedFromPresentationID == idString }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Fetch Multiple

    /// Fetch multiple Presentations with optional filtering and sorting
    func fetchAll(
        predicate: Predicate<Presentation>? = nil,
        sortBy: [SortDescriptor<Presentation>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [Presentation] {
        var descriptor = FetchDescriptor<Presentation>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch Presentations for a specific lesson
    func fetchForLesson(id lessonID: UUID) -> [Presentation] {
        let lessonIDString = lessonID.uuidString
        let predicate = #Predicate<Presentation> { $0.lessonID == lessonIDString }
        return fetchAll(predicate: predicate)
    }

    /// Fetch Presentations containing a specific student
    func fetchForStudent(id studentID: UUID) -> [Presentation] {
        // Note: This requires fetching all and filtering in memory because
        // SwiftData predicates don't support array contains operations well.
        let all = fetchAll()
        let studentIDString = studentID.uuidString
        return all.filter { $0.studentIDs.contains(studentIDString) }
    }

    // MARK: - Fetch by State

    /// Fetch draft Presentations (inbox items - unscheduled, not presented)
    func fetchDrafts() -> [Presentation] {
        let draftState = PresentationState.draft.rawValue
        let predicate = #Predicate<Presentation> { $0.stateRaw == draftState }
        return fetchAll(predicate: predicate)
    }

    /// Fetch scheduled Presentations
    func fetchScheduled() -> [Presentation] {
        let scheduledState = PresentationState.scheduled.rawValue
        let predicate = #Predicate<Presentation> { $0.stateRaw == scheduledState }
        return fetchAll(predicate: predicate, sortBy: [SortDescriptor(\.scheduledForDay)])
    }

    /// Fetch scheduled Presentations for a date range
    func fetchScheduled(from startDate: Date, to endDate: Date) -> [Presentation] {
        let scheduledState = PresentationState.scheduled.rawValue
        let predicate = #Predicate<Presentation> { p in
            p.stateRaw == scheduledState &&
            p.scheduledForDay >= startDate &&
            p.scheduledForDay < endDate
        }
        return fetchAll(predicate: predicate, sortBy: [SortDescriptor(\.scheduledForDay)])
    }

    /// Fetch scheduled Presentations for a specific day
    func fetchScheduled(for date: Date, using calendar: Calendar = AppCalendar.shared) -> [Presentation] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return fetchScheduled(from: startOfDay, to: endOfDay)
    }

    /// Fetch presented Presentations (history)
    func fetchPresented() -> [Presentation] {
        let presentedState = PresentationState.presented.rawValue
        let predicate = #Predicate<Presentation> { $0.stateRaw == presentedState }
        return fetchAll(predicate: predicate, sortBy: [SortDescriptor(\.presentedAt, order: .reverse)])
    }

    /// Fetch presented Presentations for a date range
    func fetchPresented(from startDate: Date, to endDate: Date) -> [Presentation] {
        let presentedState = PresentationState.presented.rawValue
        let predicate = #Predicate<Presentation> { p in
            p.stateRaw == presentedState &&
            p.presentedAt != nil &&
            p.presentedAt! >= startDate &&
            p.presentedAt! < endDate
        }
        return fetchAll(predicate: predicate, sortBy: [SortDescriptor(\.presentedAt, order: .reverse)])
    }

    /// Fetch active (not yet presented) Presentations
    func fetchActive() -> [Presentation] {
        let presentedState = PresentationState.presented.rawValue
        let predicate = #Predicate<Presentation> { $0.stateRaw != presentedState }
        return fetchAll(predicate: predicate)
    }

    // MARK: - Create

    /// Create a draft Presentation (inbox item)
    @discardableResult
    func createDraft(
        lessonID: UUID,
        studentIDs: [UUID],
        lesson: Lesson? = nil
    ) -> Presentation {
        let p = Presentation(
            state: .draft,
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: lesson
        )
        context.insert(p)
        return p
    }

    /// Create a draft Presentation with relationship objects
    @discardableResult
    func createDraft(
        lesson: Lesson,
        students: [Student]
    ) -> Presentation {
        let p = Presentation(
            lesson: lesson,
            students: students,
            state: .draft
        )
        context.insert(p)
        return p
    }

    /// Create a scheduled Presentation
    @discardableResult
    func createScheduled(
        lessonID: UUID,
        studentIDs: [UUID],
        scheduledFor: Date,
        lesson: Lesson? = nil
    ) -> Presentation {
        let p = Presentation(
            state: .scheduled,
            scheduledFor: scheduledFor,
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: lesson
        )
        context.insert(p)
        return p
    }

    /// Create a scheduled Presentation with relationship objects
    @discardableResult
    func createScheduled(
        lesson: Lesson,
        students: [Student],
        scheduledFor: Date
    ) -> Presentation {
        let p = Presentation(
            lesson: lesson,
            students: students,
            state: .scheduled,
            scheduledFor: scheduledFor
        )
        context.insert(p)
        return p
    }

    /// Create a presented Presentation (historical record)
    @discardableResult
    func createPresented(
        lessonID: UUID,
        studentIDs: [UUID],
        presentedAt: Date = Date(),
        lesson: Lesson? = nil
    ) -> Presentation {
        let p = Presentation(
            state: .presented,
            presentedAt: presentedAt,
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: lesson
        )
        // Snapshot lesson info if available
        if let lesson = lesson {
            p.lessonTitleSnapshot = lesson.name
            p.lessonSubheadingSnapshot = lesson.subheading
        }
        context.insert(p)
        return p
    }

    /// Create a presented Presentation with relationship objects
    @discardableResult
    func createPresented(
        lesson: Lesson,
        students: [Student],
        presentedAt: Date = Date()
    ) -> Presentation {
        let p = Presentation(
            lesson: lesson,
            students: students,
            state: .presented,
            scheduledFor: nil
        )
        p.markPresented(at: presentedAt)
        context.insert(p)
        return p
    }

    // MARK: - Update State

    /// Schedule a Presentation
    @discardableResult
    func schedule(id: UUID, for date: Date, using calendar: Calendar = AppCalendar.shared) -> Bool {
        guard let p = fetch(id: id) else { return false }
        p.schedule(for: date, using: calendar)
        return true
    }

    /// Unschedule a Presentation (move back to draft/inbox)
    @discardableResult
    func unschedule(id: UUID) -> Bool {
        guard let p = fetch(id: id) else { return false }
        p.unschedule()
        return true
    }

    /// Mark a Presentation as presented
    @discardableResult
    func markPresented(id: UUID, at date: Date = Date()) -> Bool {
        guard let p = fetch(id: id) else { return false }
        p.markPresented(at: date)
        return true
    }

    // MARK: - Update Fields

    /// Update notes for a Presentation
    @discardableResult
    func updateNotes(id: UUID, notes: String) -> Bool {
        guard let p = fetch(id: id) else { return false }
        p.notes = notes
        p.modifiedAt = Date()
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
        guard let p = fetch(id: id) else { return false }

        if let needsPractice = needsPractice {
            p.needsPractice = needsPractice
        }
        if let needsAnotherPresentation = needsAnotherPresentation {
            p.needsAnotherPresentation = needsAnotherPresentation
        }
        if let followUpWork = followUpWork {
            p.followUpWork = followUpWork
        }
        p.modifiedAt = Date()

        return true
    }

    /// Update students for a Presentation
    @discardableResult
    func updateStudents(id: UUID, studentIDs: [UUID]) -> Bool {
        guard let p = fetch(id: id) else { return false }
        p.studentIDs = studentIDs.map { $0.uuidString }
        p.updateDenormalizedKeys()
        p.modifiedAt = Date()
        return true
    }

    // MARK: - Delete

    /// Delete a Presentation by ID
    func delete(id: UUID) throws {
        guard let p = fetch(id: id) else { return }
        context.delete(p)
        try context.save()
    }

    /// Delete a Presentation
    func delete(_ presentation: Presentation) throws {
        context.delete(presentation)
        try context.save()
    }
}

// MARK: - Convenience Extensions

extension PresentationRepository {
    /// Fetch count of Presentations by state
    func count(state: PresentationState) -> Int {
        let stateRaw = state.rawValue
        let predicate = #Predicate<Presentation> { $0.stateRaw == stateRaw }
        let descriptor = FetchDescriptor<Presentation>(predicate: predicate)
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Fetch total count of all Presentations
    func countAll() -> Int {
        let descriptor = FetchDescriptor<Presentation>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Check if a lesson has been presented to specific students
    func hasBeenPresented(lessonID: UUID, studentIDs: [UUID]) -> Bool {
        let presentations = fetchForLesson(id: lessonID)
        let studentIDStrings = Set(studentIDs.map { $0.uuidString })

        for p in presentations where p.state == .presented {
            let pStudentIDs = Set(p.studentIDs)
            if pStudentIDs == studentIDStrings {
                return true
            }
        }
        return false
    }
}

// MARK: - Type Alias for Migration Compatibility

/// Type alias for backward compatibility during transition.
typealias LessonAssignmentRepository = PresentationRepository
