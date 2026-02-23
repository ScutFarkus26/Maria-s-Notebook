import Foundation
import SwiftData

@Model
final class TodoSubtask {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var orderIndex: Int
    var createdAt: Date
    var completedAt: Date?
    
    // Relationship to parent todo
    var todo: TodoItem?
    
    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        orderIndex: Int = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
