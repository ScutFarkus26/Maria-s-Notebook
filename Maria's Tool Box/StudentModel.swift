//
//  StudentModel.swift
//  Maria's Tool Box
//
//  Created by Danny De Berry on 11/26/25.
//

import Foundation
import SwiftData

@Model
final class Student {
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

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        birthday: Date,
        level: Level,
        nextLessons: [UUID] = [],
        manualOrder: Int = 0
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.birthday = birthday
        self.level = level
        self.nextLessons = nextLessons
        self.manualOrder = manualOrder
    }
}
