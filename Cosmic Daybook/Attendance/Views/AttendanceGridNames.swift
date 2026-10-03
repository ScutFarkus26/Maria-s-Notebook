import Foundation
import CoreData

/// The names on the phone attendance grids, the notebook's iPhone roll and
/// the Daybook Assistant's, where three columns leave room for little more
/// than a first name. Everywhere else the notebook's short form is always
/// "Maya S".
@MainActor
enum AttendanceGridNames {
    /// The fewest letters that still tell each child apart: the first name
    /// alone ("Ari"), the last initial only where a first name is shared
    /// ("Etty G", "Etty R"), and the full name where the initials clash too.
    static func names(for students: [CDStudent]) -> [NSManagedObjectID: String] {
        func key(_ name: String) -> String { name.trimmed().lowercased() }
        let firstNameCounts = Dictionary(grouping: students) { key($0.firstName) }.mapValues(\.count)
        let shortNameCounts = Dictionary(grouping: students) { key($0.shortName) }.mapValues(\.count)
        var names: [NSManagedObjectID: String] = [:]
        for student in students {
            let first = student.firstName.trimmed()
            if !first.isEmpty, firstNameCounts[key(first)] == 1 {
                names[student.objectID] = first
            } else if shortNameCounts[key(student.shortName)] == 1 {
                names[student.objectID] = student.shortName
            } else {
                names[student.objectID] = student.fullName
            }
        }
        return names
    }
}
