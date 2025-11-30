//
//  StudentModel.swift
//  Maria's Toolbox
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

    var id: UUID
    var firstName: String
    var lastName: String
    var birthday: Date
    var level: Level
    var nextLessons: [UUID]    // Store lesson UUIDs
    var manualOrder: Int = 0
    var dateStarted: Date? = nil

    var studentLessons: [StudentLesson] = []

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
        self.nextLessons = nextLessons
        self.manualOrder = manualOrder
    }
}

