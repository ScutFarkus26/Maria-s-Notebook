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

    var id: UUID = UUID()
    var firstName: String = ""
    var lastName: String = ""
    var nickname: String? = nil
    var birthday: Date = Date()
    // Store level as raw string for CloudKit compatibility (SwiftData doesn't support enum defaults)
    private var levelRaw: String = Level.lower.rawValue
    // CloudKit compatibility: Store UUIDs as strings
    var nextLessons: [String] = []
    var manualOrder: Int = 0
    var dateStarted: Date? = nil
    
    // Computed property for level enum
    var level: Level {
        get { Level(rawValue: levelRaw) ?? .lower }
        set { levelRaw = newValue.rawValue }
    }

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
        nickname: String? = nil,
        level: Level = .lower,
        dateStarted: Date? = nil,
        nextLessons: [UUID] = [],
        manualOrder: Int = 0
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
    }
    
    /// Convenience computed property to get nextLessons as UUIDs
    var nextLessonUUIDs: [UUID] {
        get { nextLessons.compactMap { UUID(uuidString: $0) } }
        set { nextLessons = newValue.map { $0.uuidString } }
    }
    
    // Inverse relationship for WorkNote.student (CloudKit compatibility)
    @Relationship(inverse: \WorkNote.student) var workNotes: [WorkNote]? = []
}

