// StudentTideTodosSection.swift
// A child's page: the open to-dos shared with Tide that are about her.

import CoreData
import SwiftUI

/// The open to-dos shared with Tide that name this child, by her full name,
/// her short form ("Maya S") or her first name when no other child has it
/// (`TideNameMatcher`), or that list her among their children. Hidden when
/// there are none.
struct StudentTideTodosSection: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @FetchRequest private var shared: FetchedResults<CDTodoItem>

    init(student: CDStudent) {
        self.student = student
        _shared = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: true)],
            predicate: NSPredicate(format: "isCompleted == NO AND tideLink != nil")
        )
    }

    var body: some View {
        let todos = Self.todos(Array(shared), naming: student, roster: dependencies.roster.all)
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Text("From Tide")
                    .font(.headline)
                    .padding(.horizontal, AppTheme.Spacing.xsmall)
                ForEach(todos, id: \.objectID) { todo in
                    row(todo)
                }
            }
            .padding(.vertical, AppTheme.Spacing.small)
            Divider()
                .padding(.top, AppTheme.Spacing.small)
        }
    }

    private func row(_ todo: CDTodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.small) {
            Button {
                TodoCompletionService.complete(todo)
                saveCoordinator.save(viewContext, reason: "Tick off a Tide to-do from a child's page")
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark done")
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                if let list = todo.tideListName {
                    Text(list)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let due = todo.dueDate {
                Text(due, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(todo.isOverdue ? AppColors.destructive : .secondary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }

    /// The shared to-dos about `student`.
    static func todos(_ shared: [CDTodoItem], naming student: CDStudent, roster: [CDStudent]) -> [CDTodoItem] {
        guard let id = student.id else { return [] }
        let children = roster.compactMap { child in
            child.id.map { TideNameMatcher.Child(id: $0, firstName: child.firstName, lastName: child.lastName) }
        }
        let matcher = TideNameMatcher(children: children)
        return shared.filter { todo in
            todo.resolvedStudentIDs.contains(id)
                || matcher.children(namedIn: todo.title + "\n" + todo.notes).contains(id)
        }
    }
}
