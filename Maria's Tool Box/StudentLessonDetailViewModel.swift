import SwiftUI
import SwiftData

@Observable
final class StudentLessonDetailViewModel {
    // MARK: - Dependencies
    private let modelContext: ModelContext
    let studentLesson: StudentLesson
    
    // MARK: - State
    var scheduledFor: Date?
    var givenAt: Date?
    var isPresented: Bool
    var notes: String
    var needsPractice: Bool
    var needsAnotherPresentation: Bool
    var followUpWork: String
    var selectedStudentIDs: Set<UUID>
    
    // Student picker state
    var studentSearchText: String = ""
    var studentLevelFilter: LevelFilter = .all
    
    // Sheet and alert state
    var showingAddStudentSheet = false
    var showingStudentPickerPopover = false
    var showDeleteAlert = false
    var showingMoveStudentsSheet = false
    
    // Banner state
    var showPlannedBanner = false
    var showMovedBanner = false
    var movedStudentNames: [String] = []
    
    // Move students state
    var studentsToMove: Set<UUID> = []
    
    // Internal state
    private var didPlanNext: Bool = false
    
    // MARK: - Enums
    enum LevelFilter: String, CaseIterable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
    }
    
    // MARK: - Initialization
    init(studentLesson: StudentLesson, modelContext: ModelContext) {
        self.studentLesson = studentLesson
        self.modelContext = modelContext
        
        // Initialize state from model
        self.scheduledFor = studentLesson.scheduledFor
        self.givenAt = studentLesson.givenAt
        self.isPresented = studentLesson.isPresented
        self.notes = studentLesson.notes
        self.needsPractice = studentLesson.needsPractice
        self.needsAnotherPresentation = studentLesson.needsAnotherPresentation
        self.followUpWork = studentLesson.followUpWork
        self.selectedStudentIDs = Set(studentLesson.studentIDs)
    }
    
    // MARK: - Computed Properties
    var scheduleStatusText: String {
        guard let date = scheduledFor else {
            return "Not Scheduled Yet"
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        let datePart = formatter.string(from: date)
        let hour = Calendar.current.component(.hour, from: date)
        let period = hour < 12 ? "Morning" : "Afternoon"
        return "\(datePart) in the \(period)"
    }
    
    // MARK: - Methods
    func getNextLessonInGroup(from lessons: [Lesson]) -> Lesson? {
        guard let lesson = studentLesson.lesson else { return nil }
        
        let currentSubject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return nil }
        
        let candidates = lessons
            .filter { l in
                l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
                l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
            }
            .sorted { $0.orderInGroup < $1.orderInGroup }
        
        guard let idx = candidates.firstIndex(where: { $0.id == lesson.id }), 
              idx + 1 < candidates.count else { return nil }
        
        return candidates[idx + 1]
    }
    
    func canPlanNextLesson(nextLesson: Lesson, existingStudentLessons: [StudentLesson]) -> Bool {
        return !didPlanNext && !existingStudentLessons.contains { sl in
            sl.lessonID == nextLesson.id && 
            Set(sl.studentIDs) == selectedStudentIDs && 
            sl.givenAt == nil
        }
    }
    
    func planNextLessonInGroup(
        nextLesson: Lesson,
        students: [Student],
        lessons: [Lesson]
    ) {
        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: nextLesson.id,
            studentIDs: Array(selectedStudentIDs),
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        
        newStudentLesson.students = students.filter { selectedStudentIDs.contains($0.id) }
        newStudentLesson.lesson = lessons.first(where: { $0.id == nextLesson.id })
        newStudentLesson.syncSnapshotsFromRelationships()
        
        modelContext.insert(newStudentLesson)
        try? modelContext.save()
        
        didPlanNext = true
        showBanner(.planned)
    }
    
    func moveStudentsToNewLesson(
        students: [Student],
        lessons: [Lesson]
    ) {
        guard !studentsToMove.isEmpty, let lesson = studentLesson.lesson else { return }
        
        // Get names for banner
        movedStudentNames = students
            .filter { studentsToMove.contains($0.id) }
            .map { StudentFormatter.displayName(for: $0) }
        
        // Create new lesson with moved students
        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: lesson.id,
            studentIDs: Array(studentsToMove),
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        
        newStudentLesson.students = students.filter { studentsToMove.contains($0.id) }
        newStudentLesson.lesson = lesson
        newStudentLesson.syncSnapshotsFromRelationships()
        
        modelContext.insert(newStudentLesson)
        
        // Remove students from current lesson
        selectedStudentIDs.subtract(studentsToMove)
        studentsToMove.removeAll()
        
        try? modelContext.save()
        
        showBanner(.moved)
    }
    
    private enum BannerType {
        case planned
        case moved
    }
    
    private func showBanner(_ type: BannerType) {
        switch type {
        case .planned:
            showPlannedBanner = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                showPlannedBanner = false
            }
        case .moved:
            showMovedBanner = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                showMovedBanner = false
            }
        }
    }
    
    func filteredStudents(from allStudents: [Student]) -> [Student] {
        let query = studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        let searched: [Student]
        if query.isEmpty {
            searched = allStudents
        } else {
            searched = allStudents.filter { student in
                let firstName = student.firstName.lowercased()
                let lastName = student.lastName.lowercased()
                let fullName = student.fullName.lowercased()
                return firstName.contains(query) || lastName.contains(query) || fullName.contains(query)
            }
        }
        
        let leveled = searched.filter { student in
            switch studentLevelFilter {
            case .all: return true
            case .lower: return student.level == .lower
            case .upper: return student.level == .upper
            }
        }
        
        return leveled.sorted { lhs, rhs in
            if lhs.firstName.caseInsensitiveCompare(rhs.firstName) == .orderedSame {
                return lhs.lastName.caseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return lhs.firstName.caseInsensitiveCompare(rhs.firstName) == .orderedAscending
        }
    }
    
    func save(
        students: [Student],
        lessons: [Lesson],
        workModels: [WorkModel]
    ) throws {
        // Update model with current state
        studentLesson.scheduledFor = scheduledFor
        studentLesson.givenAt = givenAt
        studentLesson.isPresented = isPresented
        studentLesson.notes = notes
        studentLesson.needsPractice = needsPractice
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.followUpWork = followUpWork
        studentLesson.studentIDs = Array(selectedStudentIDs)
        
        studentLesson.students = students.filter { selectedStudentIDs.contains($0.id) }
        studentLesson.lesson = lessons.first(where: { $0.id == studentLesson.lessonID })
        studentLesson.syncSnapshotsFromRelationships()
        
        // Auto-create practice work if needed
        if needsPractice {
            let hasPracticeWork = workModels.contains { work in
                work.studentLessonID == studentLesson.id && work.workType == .practice
            }
            
            if !hasPracticeWork {
                let practiceWork = WorkModel(
                    id: UUID(),
                    title: "Practice: \(studentLesson.lesson?.name ?? "Lesson")",
                    workType: .practice,
                    studentLessonID: studentLesson.id,
                    notes: "",
                    createdAt: Date()
                )
                practiceWork.participants = Array(selectedStudentIDs).map { sid in
                    WorkParticipantEntity(studentID: sid, completedAt: nil, work: practiceWork)
                }
                modelContext.insert(practiceWork)
            }
        }
        
        // Auto-create follow-up work if needed
        let trimmedFollowUp = followUpWork.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFollowUp.isEmpty {
            let hasDuplicateFollowUp = workModels.contains { work in
                work.studentLessonID == studentLesson.id &&
                work.workType == .followUp &&
                work.notes.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmedFollowUp) == .orderedSame
            }
            
            if !hasDuplicateFollowUp {
                let followUp = WorkModel(
                    id: UUID(),
                    title: "Follow Up: \(studentLesson.lesson?.name ?? "Lesson")",
                    workType: .followUp,
                    studentLessonID: studentLesson.id,
                    notes: trimmedFollowUp,
                    createdAt: Date()
                )
                followUp.participants = Array(selectedStudentIDs).map { sid in
                    WorkParticipantEntity(studentID: sid, completedAt: nil, work: followUp)
                }
                modelContext.insert(followUp)
            }
        }
        
        try modelContext.save()
    }
    
    func delete() throws {
        modelContext.delete(studentLesson)
        try modelContext.save()
    }
}

