import Foundation
import CoreData

// MARK: - CDStudent Enums

nonisolated extension CDStudent {
    enum Level: String, Codable, CaseIterable, Sendable {
        case lower = "Lower"
        case upper = "Upper"
        case adolescent = "Adolescent"

        /// The level a student typically moves to at a year rollover; nil at the top of the ladder.
        var suggestedPromotionTarget: Level? {
            switch self {
            case .lower: return .upper
            case .upper: return .adolescent
            case .adolescent: return nil
            }
        }
    }

    enum EnrollmentStatus: String, Codable, CaseIterable, Sendable {
        case enrolled
        case withdrawn
        case transferred
    }
}

// MARK: - Sort Descriptors

nonisolated extension CDStudent {
    /// First name, then last name (most common sort order across the app)
    nonisolated(unsafe) static let sortByName: [NSSortDescriptor] = [
        NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true),
        NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)
    ]

    /// Last name, then first name (used in attendance and agenda views)
    nonisolated(unsafe) static let sortByLastName: [NSSortDescriptor] = [
        NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true),
        NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)
    ]
}
