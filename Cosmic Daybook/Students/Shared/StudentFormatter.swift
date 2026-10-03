import Foundation

/// Consistent student name formatting used across the app.
///
/// The shortened form is the full `firstName` field followed by the last-name
/// initial with no trailing period ("Maya S", "Mary Kate R"). A student with no
/// last name shows just the first name.
/// The rule itself lives on `CDStudent` (`shortName`), which the Daybook Assistant
/// target also compiles; these are forwarders for callers holding raw name fields.
/// All methods are nonisolated to allow calling from any actor context.
enum StudentFormatter {
    /// Returns "FirstName L" (e.g. "Maya S"), or just the first name when the last name is empty.
    nonisolated static func displayName(for student: CDStudent) -> String {
        student.shortName
    }

    /// Same rule as `displayName(for:)` for callers holding raw name fields (log rows, DTOs).
    nonisolated static func displayName(firstName: String, lastName: String) -> String {
        CDStudent.shortName(firstName: firstName, lastName: lastName)
    }

    /// Returns just the trimmed first name, falling back to the full name when it is empty.
    nonisolated static func firstName(for student: CDStudent) -> String {
        let first = student.firstName.trimmed()
        return first.isEmpty ? student.fullName.trimmed() : first
    }
}
