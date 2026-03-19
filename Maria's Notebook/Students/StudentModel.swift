//
//  StudentModel.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import Foundation
import SwiftData

@Model
final class Student: Identifiable {
    // Modern indexes for 2026 - optimized for common lookups
    // Multiple indexes defined in one #Index macro (SwiftData limitation)
    #Index<Student>([\.levelRaw], [\.manualOrder], [\.modifiedAt], [\.enrollmentStatusRaw])

    enum Level: String, Codable, CaseIterable, Sendable {
        case lower = "Lower"
        case upper = "Upper"
    }

    enum EnrollmentStatus: String, Codable, CaseIterable, Sendable {
        case enrolled
        case withdrawn
    }

    var id: UUID = UUID()
    var firstName: String = ""
    var lastName: String = ""
    var nickname: String?
    var birthday: Date = Date()
    // Store level as raw string for CloudKit compatibility (SwiftData doesn't support enum defaults)
    private var levelRaw: String = Level.lower.rawValue
    // CloudKit compatibility: Store UUIDs as strings
    var nextLessons: [String] = []
    var manualOrder: Int = 0
    var dateStarted: Date?
    // Store enrollment status as raw string for CloudKit compatibility
    private var enrollmentStatusRaw: String = EnrollmentStatus.enrolled.rawValue
    var dateWithdrawn: Date?

    /// Timestamp of when this record was last modified locally.
    /// Used for smarter CloudKit conflict resolution - prefer the most recently modified record.
    var modifiedAt: Date = Date()
    
    // Computed property for level enum
    var level: Level {
        get { Level(rawValue: levelRaw) ?? .lower }
        set { levelRaw = newValue.rawValue }
    }

    // Computed property for enrollment status enum
    var enrollmentStatus: EnrollmentStatus {
        get { EnrollmentStatus(rawValue: enrollmentStatusRaw) ?? .enrolled }
        set { enrollmentStatusRaw = newValue.rawValue }
    }

    var isWithdrawn: Bool { enrollmentStatus == .withdrawn }
    var isEnrolled: Bool { enrollmentStatus == .enrolled }

    @Relationship(deleteRule: .cascade, inverse: \Document.student)
    var documents: [Document]? = []

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        birthday: Date,
        nickname: String? = nil,
        level: Level = .lower,
        dateStarted: Date? = nil,
        nextLessons: [UUID] = [],
        manualOrder: Int = 0,
        enrollmentStatus: EnrollmentStatus = .enrolled,
        dateWithdrawn: Date? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.nickname = nickname
        self.birthday = birthday
        self.levelRaw = level.rawValue
        self.dateStarted = dateStarted
        // Convert UUIDs to strings for CloudKit compatibility
        self.nextLessons = nextLessons.map { $0.uuidString }
        self.manualOrder = manualOrder
        self.enrollmentStatusRaw = enrollmentStatus.rawValue
        self.dateWithdrawn = dateWithdrawn
    }
    
    /// Convenience computed property to get nextLessons as UUIDs
    var nextLessonUUIDs: [UUID] {
        get { nextLessons.compactMap { UUID(uuidString: $0) } }
        set { nextLessons = newValue.map { $0.uuidString } }
    }
}

// MARK: - Sort Descriptors

extension Student {
    /// First name, then last name (most common sort order across the app)
    nonisolated static let sortByName: [SortDescriptor<Student>] = [
        SortDescriptor(\Student.firstName),
        SortDescriptor(\Student.lastName)
    ]

    /// Last name, then first name (used in attendance and agenda views)
    nonisolated static let sortByLastName: [SortDescriptor<Student>] = [
        SortDescriptor(\Student.lastName),
        SortDescriptor(\Student.firstName)
    ]
}
