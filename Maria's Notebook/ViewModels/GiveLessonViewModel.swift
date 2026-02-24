import SwiftUI
import SwiftData
import Foundation

// NOTE: Renamed type: GiveLessonViewModel -> LessonPickerViewModel

// MARK: - Supporting Types

enum GiveLessonMode: Hashable {
    case plan
    case given
}

enum StudentLevelFilter: String, CaseIterable {
    case all = "All"
    case lower = "Lower"
    case upper = "Upper"
}

// MARK: - View Model

@Observable
@MainActor
final class LessonPickerViewModel {
    // MARK: - Properties

    var selectedStudentIDs: Set<UUID> = []
    var scheduledFor: Date?
    var givenAt: Date?
    var notes: String = ""
    var needsPractice: Bool = false
    var needsAnotherPresentation: Bool = false
    var followUpWork: String = ""
    var selectedLessonID: UUID?
    var mode: GiveLessonMode = .plan

    // Search and UI state
    var lessonSearchText: String = ""
    var studentSearchText: String = ""
    var studentLevelFilter: StudentLevelFilter = .all
    var showFollowUpField: Bool = false
    
    // MARK: - Private Properties
    
    private var allLessons: [Lesson] = []
    private var allStudents: [Student] = []
    
    // MARK: - Initialization
    
    init(
        selectedStudentIDs: Set<UUID> = [],
        scheduledFor: Date? = nil,
        givenAt: Date? = nil,
        notes: String = "",
        needsPractice: Bool = false,
        needsAnotherPresentation: Bool = false,
        followUpWork: String = "",
        selectedLessonID: UUID? = nil,
        mode: GiveLessonMode = .plan
    ) {
        self.selectedStudentIDs = selectedStudentIDs
        self.scheduledFor = scheduledFor
        self.givenAt = givenAt
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.selectedLessonID = selectedLessonID
        self.mode = mode
    }
    
    // MARK: - Configuration
    
    func configure(lessons: [Lesson], students: [Student]) {
        self.allLessons = Self.sortLessons(lessons)
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        self.allStudents = Self.sortStudents(students.uniqueByID)

        // If a lesson is already selected and the field is empty, show its name in the search field
        if lessonSearchText.trimmed().isEmpty,
           let id = selectedLessonID,
           let l = self.allLessons.first(where: { $0.id == id }) {
            lessonSearchText = l.name
        }
    }
    
    // MARK: - Computed Properties
    
    var sortedLessons: [Lesson] {
        allLessons
    }
    
    var sortedStudents: [Student] {
        allStudents
    }
    
    var filteredLessons: [Lesson] {
        let query = lessonSearchText.normalizedForComparison()
        guard !query.isEmpty else { return sortedLessons }

        return sortedLessons.filter { lesson in
            lesson.name.lowercased().contains(query) ||
            lesson.subject.lowercased().contains(query) ||
            lesson.group.lowercased().contains(query)
        }
    }
    
    var selectedStudents: [Student] {
        sortedStudents.filter { selectedStudentIDs.contains($0.id) }
    }
    
    var filteredStudentsForPicker: [Student] {
        var filtered = sortedStudents
        
        // Apply level filter
        switch studentLevelFilter {
        case .lower:
            filtered = filtered.filter { $0.level == .lower }
        case .upper:
            filtered = filtered.filter { $0.level == .upper }
        case .all:
            break
        }
        
        // Apply search filter
        let query = studentSearchText.normalizedForComparison()
        if !query.isEmpty {
            filtered = filtered.filter { student in
                student.firstName.lowercased().contains(query) ||
                student.lastName.lowercased().contains(query) ||
                student.fullName.lowercased().contains(query)
            }
        }
        
        return filtered
    }
    
    var isValid: Bool {
        selectedLessonID != nil && !selectedStudentIDs.isEmpty
    }
    
    var shouldShowScheduleHint: Bool {
        mode == .plan && scheduledFor == nil
    }
    
    // MARK: - Actions
    
    func toggleMode() {
        withAnimation(.easeInOut) {
            mode = (mode == .plan ? .given : .plan)
        }
    }
    
    func toggleStudentSelection(_ studentID: UUID) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            if selectedStudentIDs.contains(studentID) {
                selectedStudentIDs.remove(studentID)
            } else {
                selectedStudentIDs.insert(studentID)
            }
        }
    }
    
    func removeStudent(_ studentID: UUID) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            _ = selectedStudentIDs.remove(studentID)
        }
    }
    
    func selectLesson(_ lessonID: UUID) {
        selectedLessonID = lessonID
        if let l = allLessons.first(where: { $0.id == lessonID }) {
            lessonSearchText = l.name
        } else {
            lessonSearchText = ""
        }
    }
    
    func reset() {
        lessonSearchText = ""
        studentSearchText = ""
        showFollowUpField = false
    }
    
    // MARK: - Save Logic
    
    enum SaveError: LocalizedError {
        case missingLesson
        case persistFailed(underlying: Error)
        
        var title: String {
            switch self {
            case .missingLesson: return "Choose a Lesson"
            case .persistFailed: return "Save Failed"
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .missingLesson:
                return "Please select a lesson before saving."
            case .persistFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }
    
    func save(context: ModelContext, resolvedLesson: Lesson?) throws {
        guard let finalLesson = resolvedLesson else {
            throw SaveError.missingLesson
        }
        
        // Build selected IDs and search for an existing unscheduled/unpresented match
        let selectedIDs = Array(selectedStudentIDs)
        let selectedSet = Set(selectedIDs)
        let targetLessonID = finalLesson.id
        // CloudKit compatibility: Convert UUID to String for predicate
        let targetLessonIDString = targetLessonID.uuidString
        let predicate = #Predicate<StudentLesson> { sl in
            sl.givenAt == nil && sl.lessonID == targetLessonIDString
        }
        let existingCandidates = safeFetch(FetchDescriptor<StudentLesson>(predicate: predicate), from: context)
        let existingMatch = existingCandidates.first(where: { $0.resolvedLessonID == targetLessonID && Set($0.resolvedStudentIDs) == selectedSet })

        // Either reuse existing or create a new one
        let studentLesson: StudentLesson
        let isNew: Bool
        if let match = existingMatch {
            studentLesson = match
            isNew = false
        } else {
            studentLesson = StudentLessonFactory.makeUnscheduled(
                lessonID: finalLesson.id,
                studentIDs: selectedIDs
            )
            isNew = true
        }

        // Apply current state onto the chosen record
        // CloudKit compatibility: Convert UUID to String
        studentLesson.lessonID = finalLesson.id.uuidString
        studentLesson.studentIDs = selectedIDs.map { $0.uuidString }
        studentLesson.scheduledFor = (mode == .plan ? scheduledFor : nil)
        studentLesson.givenAt = (mode == .given ? givenAt : nil)
        studentLesson.isPresented = (mode == .given)
        studentLesson.notes = notes
        studentLesson.needsPractice = needsPractice
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.followUpWork = followUpWork

        // Update relationships to mirror snapshots
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let allStudents = safeFetch(FetchDescriptor<Student>(), from: context)
        let fetchedStudents = allStudents.filter { selectedSet.contains($0.id) }
        studentLesson.students = fetchedStudents
        studentLesson.lesson = finalLesson
        
        if isNew {
            context.insert(studentLesson)
        }
        
        // WorkModel flow
        // If marking as given and practice is requested, explode per-student practice work via LifecycleService
        if mode == .given && needsPractice {
            let presentedDate = AppCalendar.startOfDay(givenAt ?? Date())
            do {
                _ = try LifecycleService.recordPresentationAndExplodeWork(
                    from: studentLesson,
                    presentedAt: presentedDate,
                    modelContext: context
                )
            } catch {
                // Ignore errors for now; caller handles thrown save errors later
            }
        }
        
        // Auto-enroll students in track if lesson belongs to a track
        // When presented
        if mode == .given {
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: finalLesson,
                studentIDs: selectedIDs.map { $0.uuidString },
                modelContext: context
            )
        }
        // When scheduled
        else if mode == .plan, scheduledFor != nil {
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: finalLesson,
                studentIDs: selectedIDs.map { $0.uuidString },
                modelContext: context
            )
        }

        // If planning (not given) and practice is requested, create active practice work per student (no presentation link)
        if mode == .plan && needsPractice {
            let lessonID = finalLesson.id
            // Fetch all WorkModels once and filter in memory (no predicates)
            let allWorkModels = safeFetch(FetchDescriptor<WorkModel>(), from: context)
            let activeRaw = WorkStatus.active.rawValue
            let reviewRaw = WorkStatus.review.rawValue
            let practiceRaw = WorkKind.practiceLesson.rawValue
            
            for studentID in selectedIDs {
                let sidString = studentID.uuidString
                // Check if WorkModel already exists for this student/lesson/practice
                let exists = allWorkModels.contains { work in
                    // Check if student is a participant
                    let hasStudent = (work.participants ?? []).contains { $0.studentID == sidString }
                    guard hasStudent else { return false }
                    // Check if work is for this lesson (via studentLessonID)
                    guard let slID = work.studentLessonID else { return false }
                    let allSLs = safeFetch(FetchDescriptor<StudentLesson>(), from: context)
                    guard let sl = allSLs.first(where: { $0.id == slID }),
                          UUID(uuidString: sl.lessonID) == lessonID else {
                        return false
                    }
                    // Check status and kind
                    return (work.statusRaw == activeRaw || work.statusRaw == reviewRaw) &&
                           (work.kindRaw ?? "") == practiceRaw
                }
                
                if !exists {
                    // Create WorkModel
                    let repository = WorkRepository(context: context)
                    do {
                        _ = try repository.createWork(
                            studentID: studentID,
                            lessonID: lessonID,
                            title: nil,
                            kind: .practiceLesson,
                            presentationID: nil,
                            scheduledDate: nil
                        )
                    } catch {
                        print("⚠️ [save] Failed to create practice work for student \(studentID): \(error)")
                    }
                }
            }
        }

        // Create follow-up work if specified (both plan and given)
        let trimmedFollowUp = followUpWork.trimmed()
        if !trimmedFollowUp.isEmpty {
            let sidStrings = selectedIDs.map { $0.uuidString }
            let lidString = finalLesson.id.uuidString
            for sid in sidStrings {
                // De-dupe by (student, lesson, kind=followUp) in active/review
                let activeRaw = WorkStatus.active.rawValue
                let reviewRaw = WorkStatus.review.rawValue
                let followRaw = WorkKind.followUpAssignment.rawValue
                let fetch = FetchDescriptor<WorkModel>(predicate: #Predicate<WorkModel> {
                    $0.studentID == sid &&
                    $0.lessonID == lidString &&
                    ($0.statusRaw == activeRaw || $0.statusRaw == reviewRaw) &&
                    ($0.kindRaw ?? "") == followRaw
                })
                let exists = safeFetch(fetch, from: context).first != nil
                if !exists {
                    guard let studentUUID = UUID(uuidString: sid),
                          let lessonUUID = UUID(uuidString: lidString) else { continue }
                    let repository = WorkRepository(context: context)
                    do {
                        let workModel = try repository.createWork(
                            studentID: studentUUID,
                            lessonID: lessonUUID,
                            title: trimmedFollowUp,
                            kind: .followUpAssignment,
                            presentationID: nil,
                            scheduledDate: nil
                        )
                        // Store follow-up text in notes
                        workModel.notes = trimmedFollowUp
                    } catch {
                        print("⚠️ [save] Failed to create follow-up work for student \(sid): \(error)")
                    }
                }
            }
        }
        
        do {
            try context.save()
        } catch {
            throw SaveError.persistFailed(underlying: error)
        }
    }
    
    // MARK: - Error Handling Helpers

    private func safeFetch<T>(_ descriptor: FetchDescriptor<T>, from context: ModelContext, functionName: String = #function) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            print("⚠️ [\(functionName)] Failed to fetch \(T.self): \(error)")
            return []
        }
    }

    // MARK: - Sorting

    private static func sortLessons(_ lessons: [Lesson]) -> [Lesson] {
        StringSorting.sortByMultipleLocalizedCaseInsensitive(
            items: lessons,
            keyPaths: [\.name, \.subject, \.group],
            fallback: { $0.id.uuidString < $1.id.uuidString }
        )
    }
    
    private static func sortStudents(_ students: [Student]) -> [Student] {
        students.sorted { lhs, rhs in
            let l = (lhs.firstName.lowercased(), lhs.lastName.lowercased())
            let r = (rhs.firstName.lowercased(), rhs.lastName.lowercased())
            if l.0 == r.0 { return l.1 < r.1 }
            return l.0 < r.0
        }
    }
    
    // MARK: - Formatting Helpers
    func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    func lessonDisplayTitle(for lesson: Lesson) -> String {
        LessonFormatter.displayTitle(
            name: lesson.name,
            subject: lesson.subject,
            group: lesson.group
        )
    }
}

