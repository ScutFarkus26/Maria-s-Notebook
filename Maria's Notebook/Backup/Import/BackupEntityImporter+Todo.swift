import Foundation
import SwiftData

// MARK: - Todo

extension BackupEntityImporter {

    // MARK: - Todo Items

    static func importTodoItems(_ dtos: [TodoItemDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<TodoItem>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }, entityBuilder: { dto in
            let t = TodoItem(id: dto.id, title: dto.title, notes: dto.notes, createdAt: dto.createdAt, orderIndex: dto.orderIndex)
            t.isCompleted = dto.isCompleted
            t.completedAt = dto.completedAt
            t.dueDate = dto.dueDate
            t.priority = TodoPriority(rawValue: dto.priorityRaw) ?? .none
            t.recurrence = RecurrencePattern(rawValue: dto.recurrenceRaw) ?? .none
            t.studentIDs = dto.studentIDs
            t.linkedWorkItemID = dto.linkedWorkItemID
            t.attachmentPaths = dto.attachmentPaths
            t.estimatedMinutes = dto.estimatedMinutes
            t.actualMinutes = dto.actualMinutes
            t.reminderDate = dto.reminderDate
            t.reflectionNotes = dto.reflectionNotes
            t.tags = dto.tags
            t.scheduledDate = dto.scheduledDate
            t.isSomeday = dto.isSomeday ?? false
            t.repeatAfterCompletion = dto.repeatAfterCompletion ?? false
            t.customIntervalDays = dto.customIntervalDays
            t.locationName = dto.locationName
            t.locationLatitude = dto.locationLatitude
            t.locationLongitude = dto.locationLongitude
            t.locationRadius = dto.locationRadius
            t.notifyOnEntry = dto.notifyOnEntry
            t.notifyOnExit = dto.notifyOnExit
            return t
        })
    }

    // MARK: - Todo Subtasks

    static func importTodoSubtasks(
        _ dtos: [TodoSubtaskDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<TodoSubtask>,
        todoCheck: EntityExistsCheck<TodoItem>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let s = TodoSubtask(id: dto.id, title: dto.title, orderIndex: dto.orderIndex, createdAt: dto.createdAt)
            s.isCompleted = dto.isCompleted
            s.completedAt = dto.completedAt
            if let todoID = dto.todoID {
                do {
                    if let todo = try todoCheck(todoID) {
                        s.todo = todo
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check todo for subtask: \(error)")
                }
            }
            modelContext.insert(s)
        }
    }

    // MARK: - Todo Templates

    static func importTodoTemplates(_ dtos: [TodoTemplateDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<TodoTemplate>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }, entityBuilder: { dto in
            let t = TodoTemplate(id: dto.id, name: dto.name, title: dto.title, notes: dto.notes, createdAt: dto.createdAt)
            t.priority = TodoPriority(rawValue: dto.priorityRaw) ?? .none
            t.defaultEstimatedMinutes = dto.defaultEstimatedMinutes
            t.defaultStudentIDs = dto.defaultStudentIDs
            t.useCount = dto.useCount
            t.tags = dto.tags ?? []
            return t
        })
    }

    // MARK: - Today Agenda Orders

    static func importTodayAgendaOrders(_ dtos: [TodayAgendaOrderDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<TodayAgendaOrder>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }, entityBuilder: { dto in
            let a = TodayAgendaOrder(
                day: dto.day,
                itemType: AgendaItemType(rawValue: dto.itemTypeRaw) ?? .lesson,
                itemID: dto.itemID,
                position: dto.position
            )
            a.id = dto.id
            return a
        })
    }
}
