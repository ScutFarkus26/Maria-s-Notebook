import Foundation
import SwiftData
import SwiftUI

@Model
final class TodoTemplate {
    var id: UUID
    var name: String // Template name (e.g., "Weekly Lesson Plan")
    var title: String // Default todo title
    var notes: String
    var createdAt: Date
    private var priorityRaw: String = TodoPriority.none.rawValue
    private var categoryRaw: String = TodoCategory.general.rawValue
    
    // Store default time estimate in minutes
    var defaultEstimatedMinutes: Int?
    
    // Store default student IDs (can be empty)
    var defaultStudentIDs: [String] = []
    
    // Template metadata
    var useCount: Int = 0 // Track how many times this template has been used
    
    var priority: TodoPriority {
        get { TodoPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
    
    var category: TodoCategory {
        get { TodoCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        title: String,
        notes: String = "",
        createdAt: Date = Date(),
        priority: TodoPriority = .none,
        category: TodoCategory = .general,
        defaultEstimatedMinutes: Int? = nil,
        defaultStudentIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.priorityRaw = priority.rawValue
        self.categoryRaw = category.rawValue
        self.defaultEstimatedMinutes = defaultEstimatedMinutes
        self.defaultStudentIDs = defaultStudentIDs
    }
    
    /// Create a new TodoItem from this template
    func createTodoFromTemplate(context: ModelContext) -> TodoItem {
        let todo = TodoItem(
            title: title,
            notes: notes,
            studentIDs: defaultStudentIDs,
            priority: priority,
            category: category
        )
        
        if let estimatedMinutes = defaultEstimatedMinutes {
            todo.estimatedMinutes = estimatedMinutes
        }
        
        context.insert(todo)
        
        // Increment use count
        useCount += 1
        
        return todo
    }
}
