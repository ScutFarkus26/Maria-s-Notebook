import Foundation
import OSLog
import SwiftData
import SwiftUI

@Observable
@MainActor
final class WorkDetailViewModel {
    private static let logger = Logger.work

    // MARK: - State
    var work: WorkModel?
    var relatedLesson: Lesson?
    var relatedLessons: [Lesson] = []
    var relatedStudent: Student?
    var workModelNotes: [Note] = []
    var relatedPresentation: LessonAssignment?
    var relatedLessonAssignments: [LessonAssignment] = []
    var resolvedPresentationID: UUID?

    var showPresentationNotes = false
    var showAddNoteSheet = false
    var noteBeingEdited: Note?
    var showScheduleSheet = false
    var showPlannedBanner = false
    var showDeleteAlert = false
    var showAddStepSheet = false
    var stepBeingEdited: WorkStep?
    var showPracticeSessionSheet = false
    var showUnlockNextLessonAlert = false
    var nextLessonToUnlock: Lesson?

    var status: WorkStatus = .active
    var workKind: WorkKind = .practiceLesson
    var workTitle: String = ""
    var checkInStyle: CheckInStyle = .flexible
    var completionOutcome: CompletionOutcome?
    var completionNote: String = ""

    var newPlanDate: Date = Date()
    var newPlanPurpose: String = "progressCheck"
    var newPlanNote: String = ""
    
    // MARK: - Dependencies
    private let workID: UUID
    private var modelContext: ModelContext?
    private var saveCoordinator: SaveCoordinator?
    
    // MARK: - Initialization
    init(workID: UUID) {
        self.workID = workID
    }

    // MARK: - Error Handling Helpers

    private func safeFetch<T>(
        _ descriptor: FetchDescriptor<T>,
        context: ModelContext,
        functionName: String = #function
    ) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.warning("\(functionName): Failed to fetch \(T.self): \(error)")
            return []
        }
    }

    // MARK: - Computed Properties
    func scheduleDates(checkIns: [WorkCheckIn]) -> WorkScheduleDates {
        WorkScheduleDateLogic.compute(forCheckIns: checkIns)
    }
    
    // PERF: Uses pre-fetched relatedLessons (same subject+group) instead of all lessons
    func likelyNextLesson() -> Lesson? {
        guard let currentLesson = relatedLesson else { return nil }
        return PlanNextLessonService.findNextLesson(
            after: currentLesson,
            in: relatedLessons
        )
    }
    
    func practiceSessions(allSessions: [PracticeSession]) -> [PracticeSession] {
        guard let work = work else { return [] }
        return allSessions
            .filter { $0.workItemIDs.contains(work.id.uuidString) }
            .sorted { $0.date > $1.date }
    }
    
    // MARK: - Data Loading
    func loadWork(modelContext: ModelContext, saveCoordinator: SaveCoordinator) {
        self.modelContext = modelContext
        self.saveCoordinator = saveCoordinator
        
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { work in
                work.id == workID
            }
        )
        
        let fetchedWork = safeFetch(descriptor, context: modelContext).first
        guard let fetchedWork = fetchedWork else {
            return
        }
        
        self.work = fetchedWork
        self.status = fetchedWork.status
        self.workTitle = fetchedWork.title
        self.workKind = fetchedWork.kind ?? .practiceLesson
        self.checkInStyle = fetchedWork.checkInStyle
        self.completionOutcome = fetchedWork.completionOutcome
        
        loadRelatedData(for: fetchedWork, modelContext: modelContext)
        loadWorkNotes(for: fetchedWork)
        resolvePresentationID(for: fetchedWork, modelContext: modelContext)
    }
    
    private func loadRelatedData(for workModel: WorkModel?, modelContext: ModelContext) {
        guard let workModel = workModel else { return }
        
        // Load student
        if let studentID = UUID(uuidString: workModel.studentID) {
            let studentDescriptor = FetchDescriptor<Student>(
                predicate: #Predicate<Student> { $0.id == studentID }
            )
            relatedStudent = safeFetch(studentDescriptor, context: modelContext).first
        }
        
        // Load lesson
        if let lessonID = UUID(uuidString: workModel.lessonID) {
            let lessonDescriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate<Lesson> { $0.id == lessonID }
            )
            relatedLesson = safeFetch(lessonDescriptor, context: modelContext).first
        }
        
        // Load related lessons
        if let currentLesson = relatedLesson {
            let subject = currentLesson.subject.trimmed()
            let group = currentLesson.group.trimmed()
            
            let descriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate<Lesson> { lesson in
                    lesson.subject.contains(subject) && lesson.group.contains(group)
                }
            )
            relatedLessons = safeFetch(descriptor, context: modelContext)
        }
        
        // PERF: Load only lesson assignments for lessons in the same subject+group
        // instead of loading all LessonAssignments via @Query
        if !relatedLessons.isEmpty {
            let relatedLessonIDs = Set(relatedLessons.map { $0.id.uuidString })
            let allLADescriptor = FetchDescriptor<LessonAssignment>()
            let allLAs = safeFetch(allLADescriptor, context: modelContext)
            relatedLessonAssignments = allLAs.filter { la in
                relatedLessonIDs.contains(la.lessonID)
            }
        }

        // Load presentation
        relatedPresentation = workModel.fetchPresentation(from: modelContext)
    }
    
    private func loadWorkNotes(for workModel: WorkModel?) {
        guard let workModel = workModel else { return }
        workModelNotes = workModel.unifiedNotes?.sorted { $0.createdAt > $1.createdAt } ?? []
    }
    
    private func resolvePresentationID(for workModel: WorkModel?, modelContext: ModelContext) {
        guard let workModel = workModel else { return }
        
        if let presentationIDString = workModel.presentationID,
           let uuid = UUID(uuidString: presentationIDString) {
            resolvedPresentationID = uuid
        }
    }
    
    // MARK: - Actions
    // PERF: Uses pre-loaded relatedLessons and relatedLessonAssignments
    func checkAndOfferUnlock() {
        guard status == .complete,
              completionOutcome == .proficient,
              relatedLesson != nil,
              let studentID = UUID(uuidString: work?.studentID ?? ""),
              let nextLesson = likelyNextLesson() else {
            return
        }

        // Find LessonAssignment for next lesson
        let nextLessonAssignment = relatedLessonAssignments.first { la in
            la.lessonIDUUID == nextLesson.id &&
            la.studentUUIDs.contains(studentID)
        }

        // Offer unlock if blocked
        if let la = nextLessonAssignment, !la.manuallyUnblocked && !la.isGiven {
            nextLessonToUnlock = nextLesson
            showUnlockNextLessonAlert = true
        }
    }

    func unlockNextLesson(modelContext: ModelContext) {
        guard let lesson = relatedLesson,
              let studentIDString = work?.studentID,
              let studentID = UUID(uuidString: studentIDString) else { return }

        _ = UnlockNextLessonService.unlockNextLesson(
            after: lesson.id,
            for: Set([studentID]),
            modelContext: modelContext,
            lessons: relatedLessons,
            lessonAssignments: relatedLessonAssignments
        )

        showScheduleSheet = true
    }
    
    func addPlan(modelContext: ModelContext) {
        guard let work = work else { return }
        
        let checkIn = WorkCheckIn(
            id: UUID(),
            workID: work.id,
            date: newPlanDate,
            status: .scheduled,
            purpose: newPlanPurpose
        )

        modelContext.insert(checkIn)
        let trimmedNote = newPlanNote.trimmed()
        if !trimmedNote.isEmpty {
            _ = checkIn.setLegacyNoteText(trimmedNote, in: modelContext)
        }
        showPlannedBanner = true
    }
    
    func save(modelContext: ModelContext, saveCoordinator: SaveCoordinator) {
        guard let work = work else { return }
        
        work.status = status
        work.kind = workKind
        work.title = workTitle
        work.checkInStyle = checkInStyle
        work.completionOutcome = completionOutcome
        
        saveCoordinator.save(modelContext)
    }
    
    func deleteWork(modelContext: ModelContext, saveCoordinator: SaveCoordinator, onDeleted: @escaping () -> Void) {
        guard let work = work else { return }
        
        modelContext.delete(work)
        saveCoordinator.save(modelContext)
        onDeleted()
    }
    
    // MARK: - Helpers
    func studentName() -> String {
        relatedStudent?.firstName ?? "Unknown"
    }
    
    func lessonTitle() -> String {
        relatedLesson?.name ?? "Unknown Lesson"
    }
    
    func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "observation": return .blue
        case "practice": return .green
        case "follow-up": return .orange
        case "general": return .gray
        default: return .purple
        }
    }
}
