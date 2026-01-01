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
    enum Level: String, Codable, CaseIterable {
        case lower = "Lower"
        case upper = "Upper"
    }

    @Attribute(.unique) var id: UUID
    var firstName: String
    var lastName: String
    var birthday: Date
    var level: Level
    // CloudKit compatibility: Store UUIDs as strings
    var nextLessons: [String] = []
    var manualOrder: Int = 0
    var dateStarted: Date? = nil

    // Note: studentLessons relationship removed because StudentLesson.students is @Transient
    // Use queries filtered by studentIDs instead to find lessons for a student
    // var studentLessons: [StudentLesson]? = [] // Removed - cannot have relationship to @Transient property

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        birthday: Date,
        level: Level,
        dateStarted: Date? = nil,
        nextLessons: [UUID] = [],
        manualOrder: Int = 0
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.birthday = birthday
        self.level = level
        self.dateStarted = dateStarted
        // Convert UUIDs to strings for CloudKit compatibility
        self.nextLessons = nextLessons.map { $0.uuidString }
        self.manualOrder = manualOrder
    }
    
    /// Convenience computed property to get nextLessons as UUIDs
    var nextLessonUUIDs: [UUID] {
        get { nextLessons.compactMap { UUID(uuidString: $0) } }
        set { nextLessons = newValue.map { $0.uuidString } }
    }
}

