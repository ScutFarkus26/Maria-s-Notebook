import Foundation
import CoreData

// MARK: - CDStudent Enums

extension CDStudent {
    enum Level: String, Codable, CaseIterable, Sendable {
        case lower = "Lower"
        case upper = "Upper"
    }

    enum EnrollmentStatus: String, Codable, CaseIterable, Sendable {
        case enrolled
        case withdrawn
    }
}

// MARK: - Sort Descriptors

extension CDStudent {
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
