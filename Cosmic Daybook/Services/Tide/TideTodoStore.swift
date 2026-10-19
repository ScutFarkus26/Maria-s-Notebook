// TideTodoStore.swift
// The notebook's to-dos as the Tide sync reads and writes them.

import CoreData
import Foundation

/// One notebook to-do, as the sync sees it.
nonisolated struct TideNotebookTodo: Equatable, Sendable {
    let id: UUID
    var title: String
    var notes: String
    var isCompleted: Bool
    /// An automatic work check-in ("Check in with Maya on …"): never sent.
    var hasLinkedWork: Bool
    /// Someday doesn't travel: a someday to-do stays here until it has a day.
    var isSomeday: Bool
    var tideLink: String?
    var studentIDs: [UUID]
    var dueDate: Date?
    /// The day it is planned for; a later one is sent as Tide's start date.
    var scheduledDate: Date?
    var createdAt: Date?
}

/// The notebook's side of the sync. Everything the sync changes in the
/// notebook goes through here, never straight to Core Data from the engine:
/// `NotebookTideTodoStore` makes the changes the Todos screens make.
protocol TideTodoStore: AnyObject {
    /// Every open to-do, and the ticked ones among `closed` that are linked.
    func todos(alsoClosed closed: Set<UUID>) -> [TideNotebookTodo]
    /// Full names of these children, in roster order where known.
    func studentNames(for ids: [UUID]) -> [String]
    /// Links a to-do to a Tide action; `title` is Tide's wording, when it differs.
    func link(_ id: UUID, to link: String, title: String?)
    /// Ticks a to-do off, as its checkbox does.
    func complete(_ id: UUID)
    /// Opens a to-do again with a new due date: a Tide repeat ticked here moved on.
    func reopen(_ id: UUID, due: Date?)
    /// Brings a to-do that was made in Tide into line with its words and date.
    func update(_ id: UUID, title: String, due: Date?)
    /// A new notebook to-do for an action made in Tide. Returns its id.
    @discardableResult
    func add(title: String, notes: String, due: Date?, link: String) -> UUID
    /// Saves what changed. False when the save failed.
    func save() -> Bool
}

/// The real store: the view context, `TodoCompletionService` for ticks (so a
/// repeating notebook to-do still gets its next occurrence) and the
/// `SaveCoordinator` every screen saves through.
final class NotebookTideTodoStore: TideTodoStore {
    private let context: NSManagedObjectContext
    private let saveCoordinator: SaveCoordinator
    private var objects: [UUID: CDTodoItem] = [:]
    /// True while the store changes or saves the context, so the change
    /// notifications that come from the sync itself don't ask for another run.
    private(set) var isWriting = false

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    func todos(alsoClosed closed: Set<UUID>) -> [TideNotebookTodo] {
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = NSPredicate(
            format: "isCompleted == NO OR (tideLink != nil AND id IN %@)", Array(closed) as NSArray
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: true)]
        objects = [:]
        var order: [UUID] = []
        for todo in context.safeFetch(request) {
            guard let id = todo.id else { continue }
            if let kept = objects[id] {
                // A CloudKit duplicate of the same id: the linked copy wins,
                // or the copy here would be sent to Tide a second time.
                if kept.tideLink == nil, todo.tideLink != nil { objects[id] = todo }
                continue
            }
            objects[id] = todo
            order.append(id)
        }
        return order.compactMap { id in objects[id].map { Self.row(id: id, $0) } }
    }

    private static func row(id: UUID, _ todo: CDTodoItem) -> TideNotebookTodo {
        TideNotebookTodo(
            id: id,
            title: todo.title,
            notes: todo.notes,
            isCompleted: todo.isCompleted,
            hasLinkedWork: !(todo.linkedWorkItemID ?? "").trimmed().isEmpty,
            isSomeday: todo.isSomeday,
            tideLink: todo.tideLink,
            studentIDs: todo.resolvedStudentIDs,
            dueDate: todo.dueDate,
            scheduledDate: todo.scheduledDate,
            createdAt: todo.createdAt
        )
    }

    func studentNames(for ids: [UUID]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", ids as NSArray)
        let byID = Dictionary(
            context.safeFetch(request).compactMap { student in student.id.map { ($0, student.fullName) } },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.compactMap { byID[$0] }
    }

    func link(_ id: UUID, to link: String, title: String?) {
        guard let todo = objects[id] else { return }
        write {
            if todo.tideLink != link { todo.tideLink = link }
            if let title, !title.isEmpty, todo.title != title { todo.title = title }
        }
    }

    func complete(_ id: UUID) {
        guard let todo = objects[id], !todo.isCompleted else { return }
        write { TodoCompletionService.complete(todo) }
    }

    func reopen(_ id: UUID, due: Date?) {
        guard let todo = objects[id] else { return }
        write {
            if todo.isCompleted { TodoCompletionService.reopen(todo) }
            if todo.dueDate != due { todo.dueDate = due }
        }
    }

    func update(_ id: UUID, title: String, due: Date?) {
        guard let todo = objects[id] else { return }
        write {
            if !title.isEmpty, todo.title != title { todo.title = title }
            if todo.dueDate != due { todo.dueDate = due }
        }
    }

    @discardableResult
    func add(title: String, notes: String, due: Date?, link: String) -> UUID {
        var id = UUID()
        write {
            let todo = CDTodoItem(context: context)
            id = todo.id ?? id
            todo.id = id
            todo.title = title
            todo.notes = notes
            todo.dueDate = due
            todo.tideLink = link
            objects[id] = todo
        }
        return id
    }

    func save() -> Bool {
        isWriting = true
        defer { isWriting = false }
        return saveCoordinator.save(context, reason: "Share to-dos with Tide", alertOnFailure: false)
    }

    /// One change, announced while `isWriting` is set: Core Data posts the
    /// context's change notification when it processes pending changes.
    private func write(_ change: () -> Void) {
        isWriting = true
        defer { isWriting = false }
        change()
        context.processPendingChanges()
    }
}
