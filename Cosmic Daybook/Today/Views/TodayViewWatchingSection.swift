// TodayViewWatchingSection.swift
// Watching section for TodayView — the WatchList rows the guide raised in
// the week that holds the selected day, grouped per child.
//
// Self-contained: the view fetches its own three sources and renders nothing
// at all when the week is empty, so TodayView only has to place it.

import CoreData
import SwiftUI

extension TodayView {

    var watchingListSection: some View {
        TodayWatchingSectionView(
            day: viewModel.date,
            onOpenNote: { noteBeingEdited = $0 },
            onOpenTodo: { selectedTodoItem = $0 },
            onOpenStudent: { appRouter.requestOpenStudentDetail($0) }
        )
    }
}

struct TodayWatchingSectionView: View {
    let day: Date
    let onOpenNote: (CDNote) -> Void
    let onOpenTodo: (CDTodoItem) -> Void
    let onOpenStudent: (UUID) -> Void

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)],
        predicate: WatchListFetcher.flaggedNotePredicate
    ) private var flaggedNotes: FetchedResults<CDNote>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: false)],
        predicate: WatchListFetcher.watchTodoPredicate
    ) private var watchTodos: FetchedResults<CDTodoItem>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDStudentFocusItem.sortOrder, ascending: true)],
        predicate: WatchListFetcher.activeGoalPredicate
    ) private var activeGoals: FetchedResults<CDStudentFocusItem>

    @FetchRequest(sortDescriptors: CDStudent.sortByName, predicate: CDStudent.enrolledPredicate)
    private var enrolledStudents: FetchedResults<CDStudent>

    @State private var itemPendingClear: WatchItem?

    /// Everything open across the roster, and the slice raised this week.
    private struct Lists {
        let open: [WatchItem]
        let week: [WatchItem]
    }

    private var lists: Lists {
        let roster = Set(enrolledStudents.compactMap(\.id))
        let open = WatchListBuilder.restricted(
            toRoster: roster,
            WatchListBuilder.build(
                notes: flaggedNotes.map(WatchNoteInput.init(note:)),
                todos: watchTodos.map(WatchTodoInput.init(todo:)),
                goals: activeGoals.map(WatchGoalInput.init(item:))
            )
        )
        let week = WatchListBuilder.touched(in: WatchListBuilder.week(containing: day), open)
        return Lists(open: open, week: week)
    }

    private var namesByID: [UUID: String] {
        Dictionary(
            enrolledStudents.compactMap { student in
                student.id.map { ($0, student.shortName) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        let lists = lists
        if !lists.week.isEmpty {
            let names = namesByID
            Section {
                ForEach(WatchListBuilder.grouped(lists.week) { names[$0] ?? "Student" }) { group in
                    groupHeader(group)
                    ForEach(group.items) { item in
                        row(item, in: lists.open)
                    }
                }
            } header: {
                header(thisWeek: lists.week.count, open: lists.open.count)
            }
        }
    }

    // MARK: - Pieces

    private func header(thisWeek: Int, open: Int) -> some View {
        HStack {
            Text("Watching")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text("\(thisWeek) this week · \(open) open")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.tertiary)
                .textCase(nil)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        // One presenter for the whole section: a modifier on the Section
        // itself would be applied to every row.
        .confirmationDialog(
            WatchClearConfirmation.title,
            isPresented: Binding(
                get: { itemPendingClear != nil },
                set: { if !$0 { itemPendingClear = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(WatchClearConfirmation.action, role: .destructive) {
                if let item = itemPendingClear { WatchListActions.clear(item, in: viewContext) }
                itemPendingClear = nil
            }
        } message: {
            Text(WatchClearConfirmation.message)
        }
    }

    @ViewBuilder
    private func groupHeader(_ group: WatchGroup) -> some View {
        if let studentID = group.studentID {
            Button {
                onOpenStudent(studentID)
            } label: {
                HStack(spacing: AppTheme.Spacing.xsmall) {
                    Text(group.name)
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(group.name)")
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 2, trailing: 20))
        } else {
            Text(group.name)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 2, trailing: 20))
        }
    }

    private func row(_ item: WatchItem, in open: [WatchItem]) -> some View {
        WatchItemRow(item: item) { openSource(item) }
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            .swipeActions(edge: .leading) {
                Button {
                    clear(item, in: open)
                } label: {
                    Label("Clear", systemImage: "checkmark")
                }
                .tint(.green)
            }
            .contextMenu {
                Button {
                    clear(item, in: open)
                } label: {
                    Label("Clear", systemImage: "checkmark.circle")
                }
            }
    }

    // MARK: - Actions

    private func clear(_ item: WatchItem, in open: [WatchItem]) {
        if WatchClearConfirmation.isNeeded(for: item, in: open) {
            itemPendingClear = item
        } else {
            // The fetch requests refresh the list once the save lands.
            WatchListActions.clear(item, in: viewContext)
        }
    }

    private func openSource(_ item: WatchItem) {
        switch WatchListActions.open(item, in: viewContext) {
        case .note(let note):
            onOpenNote(note)
        case .todo(let todo):
            onOpenTodo(todo)
        case .meeting(_, let studentID):
            // Today has no meeting-detail sheet and should not grow one; the
            // child's page shows the goal in context.
            onOpenStudent(studentID)
        case nil:
            break
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct TodayViewWatchingSectionPreview: View {
    var body: some View {
        Text("TodayWatchingSectionView requires real data")
    }
}

#Preview {
    TodayViewWatchingSectionPreview()
}
