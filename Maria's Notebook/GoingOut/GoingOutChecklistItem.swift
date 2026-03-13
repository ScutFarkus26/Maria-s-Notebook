// GoingOutChecklistItem.swift
// Checklist item for Going-Out planning steps.
// CloudKit compatible: string FK, no @Attribute(.unique).

import Foundation
import SwiftData

@Model
final class GoingOutChecklistItem: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// CloudKit-compatible FK to GoingOut
    var goingOutID: String = ""
    @Relationship var goingOut: GoingOut?

    var title: String = ""
    var isCompleted: Bool = false
    var sortOrder: Int = 0
    /// Optional student assignment for this checklist item
    var assignedToStudentID: String?

    init(
        id: UUID = UUID(),
        goingOutID: UUID,
        title: String = "",
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        assignedToStudentID: UUID? = nil
    ) {
        self.id = id
        self.goingOutID = goingOutID.uuidString
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.assignedToStudentID = assignedToStudentID?.uuidString
    }
}
