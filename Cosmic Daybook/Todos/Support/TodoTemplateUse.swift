// TodoTemplateUse.swift
// Making a todo from a template.

import CoreData
import Foundation

/// A template's "Use" button. The todo it made had the template's children
/// but none of the student tags New Todo gives them, so it was missing from
/// those children's tag lists, and a child who had left the class was still
/// put on it (bug hunt 2026-10-10, P2 #28).
enum TodoTemplateUse {

    /// A new todo from `template` in `context`, for the template's children
    /// who are still in the class (`enrolled`), each tagged by name the way
    /// New Todo tags them. Counts the use. Does not save.
    @discardableResult
    static func makeTodo(
        from template: CDTodoTemplate, enrolled: [CDStudent], in context: NSManagedObjectContext
    ) -> CDTodoItem {
        let chosen = Set(template.defaultStudentIDsArray.compactMap(UUID.init(uuidString:)))
        let students = enrolled.filter { student in student.id.map(chosen.contains) ?? false }

        let todo = CDTodoItem(context: context)
        todo.title = template.title
        todo.notes = template.notes
        todo.priority = template.priority
        if template.defaultEstimatedMinutes > 0 { todo.estimatedMinutes = template.defaultEstimatedMinutes }
        todo.studentIDsArray = students.compactMap { $0.id?.uuidString }
        todo.tagsArray = TodoTagHelper.syncStudentTags(
            existingTags: template.tagsArray,
            studentNames: students.map(\.fullName)
        )
        template.useCount += 1
        return todo
    }
}
