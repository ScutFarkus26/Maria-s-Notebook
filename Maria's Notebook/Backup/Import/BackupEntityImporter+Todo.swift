import Foundation
import CoreData
import OSLog

// MARK: - Todo

extension BackupEntityImporter {

    // MARK: - Todo Items

    static func importTodoItems(
        _ dtos: [TodoItemDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDTodoItem>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let t = CDTodoItem(context: viewContext)
            t.id = dto.id
            t.title = dto.title
            t.notes = dto.notes
            t.createdAt = dto.createdAt
            t.orderIndex = Int64(dto.orderIndex)
            t.isCompleted = dto.isCompleted
            t.completedAt = dto.completedAt
            t.dueDate = dto.dueDate
            t.priority = TodoPriority(rawValue: dto.priorityRaw) ?? .none
            t.recurrence = RecurrencePattern(rawValue: dto.recurrenceRaw) ?? .none
            t.studentIDs = dto.studentIDs as NSObject
            t.linkedWorkItemID = dto.linkedWorkItemID
            t.attachmentPaths = dto.attachmentPaths as NSObject
            t.estimatedMinutes = Int64(dto.estimatedMinutes ?? 0)
            t.actualMinutes = Int64(dto.actualMinutes ?? 0)
            t.reminderDate = dto.reminderDate
            t.reflectionNotes = dto.reflectionNotes
            t.tags = dto.tags as NSObject
            t.scheduledDate = dto.scheduledDate
            t.isSomeday = dto.isSomeday ?? false
            t.repeatAfterCompletion = dto.repeatAfterCompletion ?? false
            t.customIntervalDays = Int64(dto.customIntervalDays ?? 0)
            t.locationName = dto.locationName
            t.locationLatitude = dto.locationLatitude ?? 0
            t.locationLongitude = dto.locationLongitude ?? 0
            t.locationRadius = dto.locationRadius
            t.notifyOnEntry = dto.notifyOnEntry
            t.notifyOnExit = dto.notifyOnExit
            return t
        })
    }

    // MARK: - Todo Subtasks

    static func importTodoSubtasks(
        _ dtos: [TodoSubtaskDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDTodoSubtask>,
        todoCheck: EntityExistsCheck<CDTodoItem>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let s = CDTodoSubtask(context: viewContext)
            s.id = dto.id
            s.title = dto.title
            s.orderIndex = Int64(dto.orderIndex)
            s.createdAt = dto.createdAt
            s.isCompleted = dto.isCompleted
            s.completedAt = dto.completedAt
            if let todoID = dto.todoID {
                do {
                    if let todo = try todoCheck(todoID) {
                        s.todo = todo
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check todo for subtask: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(s)
        }
    }

    // MARK: - Todo Templates

    static func importTodoTemplates(
        _ dtos: [TodoTemplateDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDTodoTemplate>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let t = CDTodoTemplate(context: viewContext)
            t.id = dto.id
            t.name = dto.name
            t.title = dto.title
            t.notes = dto.notes
            t.createdAt = dto.createdAt
            t.priority = TodoPriority(rawValue: dto.priorityRaw) ?? .none
            t.defaultEstimatedMinutes = Int64(dto.defaultEstimatedMinutes ?? 0)
            t.defaultStudentIDs = dto.defaultStudentIDs as NSObject
            t.useCount = Int64(dto.useCount)
            t.tags = (dto.tags ?? []) as NSObject
            return t
        })
    }

    // MARK: - Today Agenda Orders

    static func importTodayAgendaOrders(
        _ dtos: [TodayAgendaOrderDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDTodayAgendaOrder>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let a = CDTodayAgendaOrder(context: viewContext)
            a.id = dto.id
            a.day = dto.day
            a.itemTypeRaw = (AgendaItemType(rawValue: dto.itemTypeRaw) ?? .lesson).rawValue
            a.itemID = dto.itemID
            a.position = Int64(dto.position)
            return a
        })
    }
}
