import SwiftUI
import SwiftData
import Foundation
import Combine

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

@MainActor
final class GiveLessonViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var selectedStudentIDs: Set<UUID> = []
    @Published var scheduledFor: Date?
    @Published var givenAt: Date?
    @Published var notes: String = ""
    @Published var needsPractice: Bool = false
    @Published var needsAnotherPresentation: Bool = false
    @Published var followUpWork: String = ""
    @Published var selectedLessonID: UUID?
    @Published var mode: GiveLessonMode = .plan
    
    // Search and UI state
    @Published var lessonSearchText: String = ""
    @Published var studentSearchText: String = ""
    @Published var studentLevelFilter: StudentLevelFilter = .all
    @Published var showFollowUpField: Bool = false
    
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
        self.allStudents = Self.sortStudents(students)

        // If a lesson is already selected and the field is empty, show its name in the search field
        if lessonSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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
        let query = lessonSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        let query = studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        
        let studentLesson = StudentLesson(
            lessonID: finalLesson.id,
            studentIDs: Array(selectedStudentIDs),
            scheduledFor: mode == .plan ? scheduledFor : nil,
            givenAt: mode == .given ? givenAt : nil,
            isPresented: (mode == .given),
            notes: notes,
            needsPractice: needsPractice,
            needsAnotherPresentation: needsAnotherPresentation,
            followUpWork: followUpWork
        )
        
        context.insert(studentLesson)
        
        // Create practice work if needed
        if needsPractice {
            let existingWorks = try? context.fetch(FetchDescriptor<WorkModel>())
            let hasPractice = (existingWorks ?? []).contains { work in
                work.studentLessonID == studentLesson.id && work.workType == .practice
            }
            if !hasPractice {
                let practiceWork = WorkModel(
                    id: UUID(),
                    studentIDs: Array(selectedStudentIDs),
                    workType: .practice,
                    studentLessonID: studentLesson.id,
                    notes: "",
                    createdAt: Date()
                )
                context.insert(practiceWork)
            }
        }
        
        // Create follow-up work if specified
        let trimmedFollowUp = followUpWork.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFollowUp.isEmpty {
            let followUp = WorkModel(
                id: UUID(),
                title: "Follow Up: \(finalLesson.name)",
                studentIDs: Array(selectedStudentIDs),
                workType: .followUp,
                studentLessonID: studentLesson.id,
                notes: trimmedFollowUp,
                createdAt: Date()
            )
            context.insert(followUp)
        }
        
        do {
            try context.save()
        } catch {
            throw SaveError.persistFailed(underlying: error)
        }
    }
    
    // MARK: - Sorting
    
    private static func sortLessons(_ lessons: [Lesson]) -> [Lesson] {
        lessons.sorted { lhs, rhs in
            if lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedSame {
                if lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedSame {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedAscending
            }
            return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
        }
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
        let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
        var suffix = ""
        if !subject.isEmpty && !group.isEmpty {
            suffix = " • \(subject) • \(group)"
        } else if !subject.isEmpty {
            suffix = " • \(subject)"
        } else if !group.isEmpty {
            suffix = " • \(group)"
        }
        return lesson.name + suffix
    }
}

