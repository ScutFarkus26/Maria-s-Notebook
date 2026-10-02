//
//  MCPNotebookTools+TodoWorkLinks.swift
//  Cosmic Daybook
//
//  A todo can be about one piece of work: `linkedWorkItemID`, the work's
//  uuidString. Today shows such a todo on the work's row instead of in the
//  Todos list (see TodayLinkedTodos). These are
//  the pieces `add_follow_up`, `update_todo` and `list_todos` share to set,
//  clear and read that link.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// The `work_id` field as both todo writers declare it.
    static let todoWorkIDSchema: JSONValue = [
        "type": "string",
        "description": .string("The work item this todo is about, as a work id from student_work "
            + "or work_detail. Pass it whenever the todo concerns one specific piece of work, so "
            + "Today shows it on that work's row instead of as a separate todo")
    ]

    /// What a write call asked for the todo's work link.
    enum TodoWorkLinkChange {
        case unchanged
        case link(CDWorkModel)
        case clear
    }

    /// Parses `work_id` (and, for `update_todo`, `clear_work_id`). A `work_id`
    /// that is null or blank asks for a clear where clearing is allowed and is
    /// ignored where it is not; any other value must name an existing work item.
    static func todoWorkLinkChange(
        _ arguments: [String: JSONValue], allowClear: Bool, in modelContext: NSManagedObjectContext
    ) throws -> TodoWorkLinkChange {
        let clearFlag = allowClear && arguments["clear_work_id"]?.boolValue == true
        switch arguments["work_id"] {
        case .none:
            return clearFlag ? .clear : .unchanged
        case .null?:
            return allowClear ? .clear : .unchanged
        case .string(let text)?:
            guard let reference = nonEmpty(text) else { return allowClear ? .clear : .unchanged }
            guard !clearFlag else {
                throw MCPToolError("Pass work_id or clear_work_id, not both.")
            }
            return .link(try resolveWork(reference, in: modelContext))
        case .some:
            throw MCPToolError("work_id must be a work item's uuid string.")
        }
    }

    /// Applies a parsed change and returns the receipt phrase, if anything changed.
    static func applyTodoWorkLink(_ change: TodoWorkLinkChange, to todo: CDTodoItem) -> String? {
        switch change {
        case .unchanged:
            return nil
        case .link(let work):
            todo.linkedWorkItemID = work.id?.uuidString
            return workLinkPhrase(work)
        case .clear:
            guard todo.linkedWorkItemID != nil else { return "no work link to clear" }
            todo.linkedWorkItemID = nil
            return "unlinked from its work"
        }
    }

    /// "linked to work "Map of the World" (work_id …)". Not a `[work id=…]`
    /// citation: the write journal's citations are what a call changed, and
    /// linking a todo leaves the work itself untouched.
    static func workLinkPhrase(_ work: CDWorkModel) -> String {
        "linked to work \"\(title(of: work))\" (work_id \(citationID(work.id)))"
    }

    /// Titles of the work items `todos` link to, keyed by the stored id
    /// string, in one fetch.
    static func linkedWorkTitles(
        for todos: [CDTodoItem], in modelContext: NSManagedObjectContext
    ) -> [String: String] {
        let ids = Set(todos.compactMap { $0.linkedWorkItemID.flatMap(UUID.init(uuidString:)) })
        guard !ids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        var titles: [String: String] = [:]
        for work in modelContext.safeFetch(request) {
            guard let id = work.id else { continue }
            titles[id.uuidString] = title(of: work)
        }
        return titles
    }

    /// The read-side detail for a linked todo: `linked_work_id=<id> "<title>"`,
    /// or a note that the work is gone.
    static func linkedWorkDetail(of todo: CDTodoItem, titles: [String: String]) -> String? {
        guard let raw = nonEmpty(todo.linkedWorkItemID) else { return nil }
        let key = UUID(uuidString: raw)?.uuidString ?? raw
        guard let title = titles[key] else {
            return "linked_work_id=\(raw) (work not found)"
        }
        return "linked_work_id=\(key) \"\(title)\""
    }
}
