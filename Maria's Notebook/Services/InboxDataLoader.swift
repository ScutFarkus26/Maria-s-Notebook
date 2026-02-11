import Foundation
import SwiftData

/// Reusable data loader for Inbox/Today style views.
/// Provides filtered fetches using FetchDescriptor to avoid loading entire tables.
@MainActor
final class InboxDataLoader {
    private let context: ModelContext
    
    init(context: ModelContext) {
        self.context = context
    }
    
    // MARK: - Main Load Method
    
    /// Loads all data needed for the Follow-Up Inbox view.
    /// Returns filtered data to minimize memory usage and improve performance.
    func loadInboxData() -> InboxData {
        // Load presented student lessons (for lesson follow-ups)
        let presentedStudentLessons = loadPresentedStudentLessons()
        
        // Load active/review work models (for work check-ins/reviews)
        let workModels = loadActiveWorkModels()
        
        // Load plan items and notes only for the work models we need
        let workIDs = Set(workModels.map { $0.id })
        let planItems = loadPlanItems(for: workIDs)
        let notes = loadNotes(for: workIDs)
        
        // Collect referenced student and lesson IDs
        var studentIDs = Set<UUID>()
        var lessonIDs = Set<UUID>()
        
        for sl in presentedStudentLessons {
            studentIDs.formUnion(sl.resolvedStudentIDs)
            lessonIDs.insert(sl.resolvedLessonID)
        }
        
        for work in workModels {
            if let sid = UUID(uuidString: work.studentID) {
                studentIDs.insert(sid)
            }
            if let lid = UUID(uuidString: work.lessonID) {
                lessonIDs.insert(lid)
            }
        }
        
        // Load only referenced students and lessons
        let students = loadStudents(ids: studentIDs)
        let lessons = loadLessons(ids: lessonIDs)
        
        return InboxData(
            studentLessons: presentedStudentLessons,
            planItems: planItems,
            notes: notes,
            students: students,
            lessons: lessons
        )
    }
    
    // MARK: - Individual Fetch Methods
    
    /// Loads student lessons that have been presented (isPresented || givenAt != nil).
    /// This is the filtered set needed for lesson follow-up calculations.
    /// Note: SwiftData predicates don't support OR conditions well, so we fetch by isPresented
    /// (the most common case) and also check givenAt. In practice, most presented lessons
    /// have isPresented=true, so this significantly reduces the dataset.
    func loadPresentedStudentLessons() -> [StudentLesson] {
        // PERFORMANCE: Fetch lessons with isPresented == true first (stored property, filtered at DB level)
        let isPresentedDescriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.isPresented == true }
        )
        let byIsPresented = context.safeFetch(isPresentedDescriptor)

        // Build a Set of IDs we already have to avoid duplicates
        let existingIDs = Set(byIsPresented.map { $0.id })

        // Also need lessons with givenAt != nil but isPresented == false
        // SwiftData predicates don't handle optional Date comparisons well,
        // so we fetch non-presented lessons and filter for givenAt != nil
        let notPresentedDescriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.isPresented == false }
        )
        let notPresented = context.safeFetch(notPresentedDescriptor)
        let withGivenAtOnly = notPresented.filter { sl in
            sl.givenAt != nil && !existingIDs.contains(sl.id)
        }

        // Combine (no Set conversion needed since we pre-filtered duplicates)
        return byIsPresented + withGivenAtOnly
    }
    
    /// Loads active and review work models (preferred).
    /// This is the filtered set needed for work check-in and review calculations.
    func loadActiveWorkModels() -> [WorkModel] {
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.statusRaw == activeRaw || work.statusRaw == reviewRaw
            }
        )
        return context.safeFetch(descriptor)
    }
    
    /// Loads plan items only for the specified work IDs.
    // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
    // so we fetch all and filter in memory
    func loadPlanItems(for workIDs: Set<UUID>) -> [WorkPlanItem] {
        guard !workIDs.isEmpty else { return [] }

        let workIDStrings = Set(workIDs.map { $0.uuidString })
        var descriptor = FetchDescriptor<WorkPlanItem>()
        descriptor.fetchLimit = 2000 // Safety limit: prevents memory issues with large datasets
        let allItems = context.safeFetch(descriptor)
        return allItems.filter { workIDStrings.contains($0.workID) }
    }
    
    /// Loads notes only for the specified work IDs.
    func loadNotes(for workIDs: Set<UUID>) -> [Note] {
        guard !workIDs.isEmpty else { return [] }

        // PERFORMANCE: Fetch notes with work relationship, then filter in Swift using Set for O(1) lookup
        // SwiftData doesn't support filtering by relationship ID directly in predicates
        let workDescriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.work != nil }
        )
        let allNotesWithWork = context.safeFetch(workDescriptor)

        // workIDs is already a Set, so .contains is O(1)
        return allNotesWithWork.filter { note in
            guard let work = note.work else { return false }
            return workIDs.contains(work.id)
        }
    }
    
    /// Loads students by their IDs.
    // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
    // so we fetch all and filter in memory
    func loadStudents(ids: Set<UUID>) -> [Student] {
        guard !ids.isEmpty else { return [] }

        var descriptor = FetchDescriptor<Student>()
        descriptor.fetchLimit = 500 // Safety limit: reasonable maximum for student roster
        let allStudents = context.safeFetch(descriptor)
        let filtered = allStudents.filter { ids.contains($0.id) }
        return TestStudentsFilter.filterVisible(filtered)
    }

    /// Loads lessons by their IDs.
    // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
    // so we fetch all and filter in memory
    func loadLessons(ids: Set<UUID>) -> [Lesson] {
        guard !ids.isEmpty else { return [] }

        var descriptor = FetchDescriptor<Lesson>()
        descriptor.fetchLimit = 1000 // Safety limit: reasonable maximum for lesson library
        let allLessons = context.safeFetch(descriptor)
        return allLessons.filter { ids.contains($0.id) }
    }
}

// MARK: - Data Structure

/// Container for inbox data loaded by InboxDataLoader.
struct InboxData {
    let studentLessons: [StudentLesson]
    let planItems: [WorkPlanItem]
    let notes: [Note]
    let students: [Student]
    let lessons: [Lesson]
}
