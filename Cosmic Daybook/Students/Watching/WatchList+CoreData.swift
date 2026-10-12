// WatchList+CoreData.swift
// Builds the WatchList's value inputs from managed objects.
//
// Kept apart from the rule itself so `WatchListBuilder` stays pure and
// testable. Nothing here decides anything — it only reads.

import CoreData
import Foundation

// MARK: - Inputs

extension WatchNoteInput {
    init(note: CDNote) {
        self.init(
            id: note.id ?? UUID(),
            needsFollowUp: note.needsFollowUp,
            studentIDs: note.scope.studentIDs,
            body: note.body,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt
        )
    }
}

extension WatchTodoInput {
    init(todo: CDTodoItem) {
        self.init(
            id: todo.id ?? UUID(),
            title: todo.title,
            studentIDs: todo.resolvedStudentIDs,
            isCompleted: todo.isCompleted,
            isSomeday: todo.isSomeday,
            createdAt: todo.createdAt,
            dueDate: todo.dueDate
        )
    }
}

extension WatchGoalInput {
    init(item: CDStudentFocusItem) {
        self.init(
            id: item.id ?? UUID(),
            studentID: item.studentIDUUID,
            text: item.text,
            isActive: item.isActive,
            createdAt: item.createdAt,
            sortOrder: Int(item.sortOrder)
        )
    }
}

// MARK: - Fetching

/// Reads the three sources and hands them to the rule.
///
/// The fetch predicates and `WatchListBuilder.isWatchTodo` must agree: a
/// `@FetchRequest` that uses `watchTodoPredicate` sees the same todos the
/// builder keeps. `WatchListFetcherTests` pins both.
@MainActor
enum WatchListFetcher {

    /// `needsFollowUp == YES` — small today (a dozen or so), never all notes.
    nonisolated(unsafe) static let flaggedNotePredicate = NSPredicate(format: "needsFollowUp == YES")

    /// Open todos whose title begins with "watch", in any case.
    nonisolated(unsafe) static let watchTodoPredicate = NSPredicate(
        format: "isCompleted == NO AND title BEGINSWITH[cd] %@", "watch"
    )

    /// Focus items still open.
    nonisolated(unsafe) static let activeGoalPredicate = NSPredicate(
        format: "statusRaw == %@", FocusItemStatus.active.rawValue
    )

    /// Every row across the class, sorted as the builder sorts.
    static func fetchAll(in context: NSManagedObjectContext) -> [WatchItem] {
        let noteRequest = CDFetchRequest(CDNote.self)
        noteRequest.predicate = flaggedNotePredicate
        let todoRequest = CDFetchRequest(CDTodoItem.self)
        todoRequest.predicate = watchTodoPredicate
        let goalRequest = CDFetchRequest(CDStudentFocusItem.self)
        goalRequest.predicate = activeGoalPredicate

        return WatchListBuilder.build(
            notes: context.safeFetch(noteRequest).map(WatchNoteInput.init(note:)),
            todos: context.safeFetch(todoRequest).map(WatchTodoInput.init(todo:)),
            goals: context.safeFetch(goalRequest).map(WatchGoalInput.init(item:))
        )
    }

    /// The ids of every child currently enrolled, less the test students the
    /// guide hides (nil reads her setting). MCP's `watching_only` listed them
    /// (bug hunt 2026-10-12 #51).
    static func enrolledIDs(
        in context: NSManagedObjectContext, showTestStudents: Bool? = nil, testStudentNames: String? = nil
    ) -> Set<UUID> {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        let visible = TestStudentsFilter.filterVisible(
            context.safeFetch(request), show: showTestStudents, namesRaw: testStudentNames
        )
        return Set(visible.compactMap(\.id))
    }
}
