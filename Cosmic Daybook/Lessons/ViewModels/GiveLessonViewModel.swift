import SwiftUI
import CoreData
import Foundation

// NOTE: Renamed type: GiveLessonViewModel -> CDLessonPickerViewModel

// MARK: - Supporting Types

enum GiveLessonMode: Hashable {
    case plan
    case given
}

// MARK: - View Model

@Observable
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
    var showFollowUpField: Bool = false
    
    // MARK: - Private Properties
    
    private var allLessons: [CDLesson] = []
    private var allStudents: [CDStudent] = []
    
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
    
    func configure(lessons: [CDLesson], students: [CDStudent]) {
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
    
    var sortedLessons: [CDLesson] {
        allLessons
    }
    
    var filteredLessons: [CDLesson] {
        let query = lessonSearchText.normalizedForComparison()
        guard !query.isEmpty else { return sortedLessons }

        return sortedLessons.filter { lesson in
            lesson.name.lowercased().contains(query) ||
            lesson.area.lowercased().contains(query) ||
            lesson.sequence.lowercased().contains(query)
        }
    }
    
    // MARK: - Actions

    func selectLesson(_ lessonID: UUID) {
        selectedLessonID = lessonID
        if let l = allLessons.first(where: { $0.id == lessonID }) {
            lessonSearchText = l.name
        } else {
            lessonSearchText = ""
        }
    }
    
    // MARK: - Sorting

    private static func sortLessons(_ lessons: [CDLesson]) -> [CDLesson] {
        StringSorting.sortByMultipleLocalizedCaseInsensitive(
            items: lessons,
            keyPaths: [\.name, \.area, \.sequence],
            fallback: { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        )
    }
    
    private static func sortStudents(_ students: [CDStudent]) -> [CDStudent] {
        students.sorted { lhs, rhs in
            let l = (lhs.firstName.lowercased(), lhs.lastName.lowercased())
            let r = (rhs.firstName.lowercased(), rhs.lastName.lowercased())
            if l.0 == r.0 { return l.1 < r.1 }
            return l.0 < r.0
        }
    }
    
    // MARK: - Formatting Helpers

    func lessonDisplayTitle(for lesson: CDLesson) -> String {
        LessonFormatter.displayTitle(
            name: lesson.name,
            area: lesson.area,
            sequence: lesson.sequence
        )
    }
}
