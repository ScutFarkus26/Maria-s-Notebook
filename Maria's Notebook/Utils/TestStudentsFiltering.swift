import Foundation

/// Shared utilities for filtering test students by name.
/// Consolidates test student filtering logic used across multiple view models.
enum TestStudentsFiltering {
    /// Normalizes test student names from a comma/semicolon-separated string.
    /// - Parameter namesRaw: Raw string containing test student names
    /// - Returns: Set of normalized (lowercased, trimmed) names
    static func normalizedHiddenNames(from namesRaw: String) -> Set<String> {
        let lower = namesRaw.lowercased()
        let parts = lower.split(whereSeparator: { ch in ch == "," || ch == ";" || ch.isNewline })
        let tokens = parts.map { String($0).trimmed() }.filter { !$0.isEmpty }
        return Set(tokens)
    }
    
    /// Filters students to exclude those matching test student names.
    /// - Parameters:
    ///   - students: Array of students to filter
    ///   - showTestStudents: Whether to show test students
    ///   - testStudentNames: Comma/semicolon-separated list of test student names
    /// - Returns: Filtered array of visible students
    static func filterVisible(
        students: [Student],
        showTestStudents: Bool,
        testStudentNames: String
    ) -> [Student] {
        guard !showTestStudents else { return students }
        
        let hiddenNames = normalizedHiddenNames(from: testStudentNames)
        guard !hiddenNames.isEmpty else { return students }
        
        return students.filter { student in
            let name = student.fullName.trimmed().lowercased()
            return !hiddenNames.contains(name)
        }
    }
}




