import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class WorkDetailViewModel: ObservableObject {
    // MARK: - Published State
    @Published var work: WorkModel?
    @Published var relatedLesson: Lesson?
    @Published var relatedLessons: [Lesson] = []
    @Published var relatedStudent: Student?
    @Published var workModelNotes: [Note] = []
    @Published var relatedPresentation: LessonAssignment?
    @Published var resolvedPresentationID: UUID?
    
    @Published var showPresentationNotes = false
    @Published var showAddNoteSheet = false
    @Published var noteBeingEdited: Note?
    @Published var showScheduleSheet = false
    @Published var showPlannedBanner = false
    @Published var showDeleteAlert = false
    @Published var showAddStepSheet = false
    @Published var stepBeingEdited: WorkStep?
    @Published var showGroupPracticeSheet = false
    @Published var showUnlockNextLessonAlert = false
    @Published var nextLessonToUnlock: Lesson?
    
    @Published var status: WorkStatus = .active
    @Published var workKind: WorkKind = .practiceLesson
    @Published var workTitle: String = ""
    @Published var completionOutcome: CompletionOutcome?
    @Published var completionNote: String = ""
    
    @Published var newPlanDate: Date = Date()
    @Published var newPlanReason: WorkPlanItem.Reason = .progressCheck
    @Published var newPlanNote: String = ""
    
    // MARK: - Dependencies
    private let workID: UUID
    private var modelContext: ModelContext?
    private var saveCoordinator: SaveCoordinator?
    
    // MARK: - Initialization
    init(workID: UUID) {
        self.workID = workID
    }
    
    // MARK: - Computed Properties
    func scheduleDates(planItems: [WorkPlanItem]) -> WorkScheduleDates {
        WorkScheduleDateLogic.compute(forPlanItems: planItems)
    }
    
    func likelyNextLesson(allLessons: [Lesson]) -> Lesson? {
        guard let currentLesson = relatedLesson else { return nil }
        return PlanNextLessonService.findNextLesson(
            after: currentLesson,
            in: relatedLessons.isEmpty ? allLessons : relatedLessons
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
        
        guard let fetchedWork = try? modelContext.fetch(descriptor).first else {
            return
        }
        
        self.work = fetchedWork
        self.status = fetchedWork.status
        self.workTitle = fetchedWork.title
        self.workKind = fetchedWork.kind ?? .practiceLesson
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
            relatedStudent = try? modelContext.fetch(studentDescriptor).first
        }
        
        // Load lesson
        if let lessonID = UUID(uuidString: workModel.lessonID) {
            let lessonDescriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate<Lesson> { $0.id == lessonID }
            )
            relatedLesson = try? modelContext.fetch(lessonDescriptor).first
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
            relatedLessons = (try? modelContext.fetch(descriptor)) ?? []
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
    func checkAndOfferUnlock(
        allLessons: [Lesson],
        allStudentLessons: [StudentLesson]
    ) {
        guard status == .complete,
              completionOutcome == .mastered,
              let currentLesson = relatedLesson,
              let studentID = UUID(uuidString: work?.studentID ?? ""),
              let nextLesson = likelyNextLesson(allLessons: allLessons) else {
            return
        }
        
        // Find StudentLesson for next lesson
        let nextStudentLesson = allStudentLessons.first { sl in
            sl.resolvedLessonID == nextLesson.id &&
            sl.resolvedStudentIDs.contains(studentID)
        }
        
        // Offer unlock if blocked
        if let sl = nextStudentLesson, !sl.manuallyUnblocked && !sl.isGiven {
            nextLessonToUnlock = nextLesson
            showUnlockNextLessonAlert = true
        }
    }
    
    func unlockNextLesson(
        allLessons: [Lesson],
        allStudentLessons: [StudentLesson],
        modelContext: ModelContext
    ) {
        guard let lesson = relatedLesson,
              let studentIDString = work?.studentID,
              let studentID = UUID(uuidString: studentIDString) else { return }
        
        _ = UnlockNextLessonService.unlockNextLesson(
            after: lesson.id,
            for: Set([studentID]),
            modelContext: modelContext,
            lessons: allLessons,
            studentLessons: allStudentLessons
        )
        
        showScheduleSheet = true
    }
    
    func addPlan(modelContext: ModelContext) {
        guard let work = work else { return }
        
        let planItem = WorkPlanItem(
            workID: work.id,
            scheduledDate: newPlanDate,
            reason: newPlanReason
        )
        
        modelContext.insert(planItem)
        showPlannedBanner = true
    }
    
    func save(modelContext: ModelContext, saveCoordinator: SaveCoordinator) {
        guard let work = work else { return }
        
        work.status = status
        work.kind = workKind
        work.title = workTitle
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
