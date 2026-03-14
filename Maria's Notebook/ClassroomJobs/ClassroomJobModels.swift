// ClassroomJobModels.swift
// SwiftData models for classroom job rotation.

import Foundation
import SwiftData
import SwiftUI

@Model
final class ClassroomJob: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var name: String = ""
    var jobDescription: String = ""
    var icon: String = "star"
    var colorRaw: String = "blue"
    var sortOrder: Int = 0
    var isActive: Bool = true
    var maxStudents: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \JobAssignment.job)
    var assignments: [JobAssignment]? = []

    var color: Color {
        switch colorRaw {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        default: return .gray
        }
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        jobDescription: String = "",
        icon: String = "star",
        colorRaw: String = "blue",
        sortOrder: Int = 0,
        isActive: Bool = true,
        maxStudents: Int = 1
    ) {
        self.id = id
        self.name = name
        self.jobDescription = jobDescription
        self.icon = icon
        self.colorRaw = colorRaw
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.maxStudents = maxStudents
    }
}

@Model
final class JobAssignment: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var jobID: String = ""
    var job: ClassroomJob?
    var studentID: String = ""
    var weekStartDate: Date = Date()
    var isCompleted: Bool = false

    var studentUUID: UUID? {
        UUID(uuidString: studentID)
    }

    init(
        id: UUID = UUID(),
        jobID: String = "",
        studentID: String = "",
        weekStartDate: Date = Date(),
        isCompleted: Bool = false
    ) {
        self.id = id
        self.jobID = jobID
        self.studentID = studentID
        self.weekStartDate = weekStartDate
    }
}
