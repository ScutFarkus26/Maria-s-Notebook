import Foundation

/// Consistent student name formatting used across the app.
///
/// The shortened form is the full `firstName` field followed by the last-name
/// initial with no trailing period ("Maya S", "Mary Kate R"). A student with no
/// last name shows just the first name.
/// All methods are nonisolated to allow calling from any actor context.
enum StudentFormatter {
    /// Returns "FirstName L" (e.g. "Maya S"), or just the first name when the last name is empty.
    nonisolated static func displayName(for student: CDStudent) -> String {
        displayName(firstName: student.firstName, lastName: student.lastName)
    }

    /// Same rule as `displayName(for:)` for callers holding raw name fields (log rows, DTOs).
    nonisolated static func displayName(firstName: String, lastName: String) -> String {
        let first = firstName.trimmed()
        let last = lastName.trimmed()
        guard !first.isEmpty else { return last }
        guard let initial = last.first else { return first }
        return "\(first) \(String(initial).uppercased())"
    }

    /// Returns just the trimmed first name, falling back to the full name when it is empty.
    nonisolated static func firstName(for student: CDStudent) -> String {
        let first = student.firstName.trimmed()
        return first.isEmpty ? student.fullName.trimmed() : first
    }
}
