import Foundation
import CoreData

/// Centralized service for resolving student and lesson names from IDs.
/// Eliminates duplicate name resolution logic across the codebase.
enum PresentationResolver {
    
    // MARK: - CDStudent Name Resolution
    
    /// Resolves a student's display name from their ID using the provided lookup dictionary.
    /// Uses StudentFormatter.displayName for consistent formatting.
    /// - Parameters:
    ///   - studentID: The UUID of the student
    ///   - studentsByID: Dictionary mapping student UUIDs to CDStudent objects
    /// - Returns: Formatted display name, or "Student" if not found
    static func displayName(for studentID: UUID, studentsByID: [UUID: CDStudent]) -> String {
        guard let student = studentsByID[studentID] else { return "Student" }
        return StudentFormatter.displayName(for: student)
    }
    
    /// Resolves a student's first name from their ID.
    /// - Parameters:
    ///   - studentID: The UUID of the student
    ///   - studentsByID: Dictionary mapping student UUIDs to CDStudent objects
    /// - Returns: First name, or "Student" if not found
    static func firstName(for studentID: UUID, studentsByID: [UUID: CDStudent]) -> String {
        guard let student = studentsByID[studentID] else { return "Student" }
        return student.firstName
    }
    
    // MARK: - CDLesson Name Resolution
    
    /// Resolves a lesson's name from its ID.
    /// - Parameters:
    ///   - lessonID: The UUID of the lesson
    ///   - lessonsByID: Dictionary mapping lesson UUIDs to CDLesson objects
    /// - Returns: CDLesson name, or "Lesson" if not found
    static func lessonName(for lessonID: UUID, lessonsByID: [UUID: CDLesson]) -> String {
        guard let lesson = lessonsByID[lessonID] else { return "Lesson" }
        return lesson.name
    }
    
    // MARK: - Work-Based Resolution

    /// Resolves both student and lesson names from a CDWorkModel.
    /// - Parameters:
    ///   - work: The CDWorkModel to resolve names from
    ///   - studentsByID: Dictionary mapping student UUIDs to CDStudent objects
    ///   - lessonsByID: Dictionary mapping lesson UUIDs to CDLesson objects
    ///   - studentNameStyle: How to format the student name (default: .displayName)
    /// - Returns: Tuple with (studentName, lessonName)
    static func resolveNames(
        for work: CDWorkModel,
        studentsByID: [UUID: CDStudent],
        lessonsByID: [UUID: CDLesson],
        studentNameStyle: StudentNameStyle = .displayName
    ) -> (student: String, lesson: String) {
        let studentName: String
        if let sid = UUID(uuidString: work.studentID) {
            switch studentNameStyle {
            case .displayName:
                studentName = displayName(for: sid, studentsByID: studentsByID)
            case .firstName:
                studentName = firstName(for: sid, studentsByID: studentsByID)
            }
        } else {
            studentName = "Student"
        }

        let lessonName: String
        if let lid = UUID(uuidString: work.lessonID) {
            lessonName = self.lessonName(for: lid, lessonsByID: lessonsByID)
        } else {
            lessonName = "Lesson"
        }

        return (studentName, lessonName)
    }
    
    /// Style for formatting student names
    enum StudentNameStyle {
        case displayName  // Uses StudentFormatter.displayName (handles duplicates)
        case firstName    // Uses student.firstName
    }
}
