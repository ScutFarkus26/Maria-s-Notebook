// StudentWatchingSection.swift
// The one place on a child's page that says what the guide is keeping an eye
// on: her flagged observations, the "Watch…" todos that name her, and her
// open goals — the WatchList, drawn for one child.

import CoreData
import SwiftUI

struct StudentWatchingSection: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @FetchRequest private var flaggedNotes: FetchedResults<CDNote>
    @FetchRequest private var watchTodos: FetchedResults<CDTodoItem>
    @FetchRequest private var activeGoals: FetchedResults<CDStudentFocusItem>

    @State private var noteBeingEdited: CDNote?
    @State private var todoBeingEdited: CDTodoItem?
    @State private var meetingBeingShown: CDStudentMeeting?
    @State private var itemPendingClear: WatchItem?

    init(student: CDStudent) {
        self.student = student
        _flaggedNotes = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)],
            predicate: WatchListFetcher.flaggedNotePredicate
        )
        _watchTodos = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: false)],
            predicate: WatchListFetcher.watchTodoPredicate
        )
        _activeGoals = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDStudentFocusItem.sortOrder, ascending: true)],
            predicate: NSPredicate(
                format: "studentID == %@ AND statusRaw == %@",
                student.id?.uuidString ?? "",
                FocusItemStatus.active.rawValue
            )
        )
    }

    /// Every row across the class — kept so a note shared with other children
    /// can say so before its flag is cleared.
    private var allItems: [WatchItem] {
        WatchListBuilder.build(
            notes: flaggedNotes.map(WatchNoteInput.init(note:)),
            todos: watchTodos.map(WatchTodoInput.init(todo:)),
            goals: activeGoals.map(WatchGoalInput.init(item:))
        )
    }

    var body: some View {
        let all = allItems
        let items = student.id.map { WatchListBuilder.items(for: $0, in: all) } ?? []
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            header(count: items.count)
            if items.isEmpty {
                Text("Nothing being watched.")
                    .foregroundStyle(.secondary)
                    .padding(.top, AppTheme.Spacing.verySmall)
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(items) { item in
                        row(item, in: all)
                    }
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .modifier(StudentWatchingSheets(
            noteBeingEdited: $noteBeingEdited,
            todoBeingEdited: $todoBeingEdited,
            meetingBeingShown: $meetingBeingShown
        ))
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
        #if os(macOS)
        .onChange(of: noteBeingEdited?.id) { _, _ in
            guard let noteID = noteBeingEdited?.id else { return }
            openWindow(id: "NoteEditorWindow", value: noteID)
            noteBeingEdited = nil
        }
        #endif
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Watching")
                .font(AppTheme.ScaledFont.header)
            Spacer()
            Text("\(count)")
                .font(AppTheme.ScaledFont.calloutSemibold)
                .foregroundStyle(.secondary)
        }
        .padding(.top, AppTheme.Spacing.xsmall)
    }

    private func row(_ item: WatchItem, in all: [WatchItem]) -> some View {
        WatchItemRow(item: item) { open(item) }
            .padding(.horizontal, AppTheme.Spacing.xsmall)
            .contextMenu {
                Button {
                    clear(item, in: all)
                } label: {
                    Label("Clear", systemImage: "checkmark.circle")
                }
            }
    }

    private func clear(_ item: WatchItem, in all: [WatchItem]) {
        if WatchClearConfirmation.isNeeded(for: item, in: all) {
            itemPendingClear = item
        } else {
            WatchListActions.clear(item, in: viewContext)
        }
    }

    private func open(_ item: WatchItem) {
        switch WatchListActions.open(item, in: viewContext) {
        case .note(let note):
            noteBeingEdited = note
        case .todo(let todo):
            todoBeingEdited = todo
        case .meeting(let meeting, _):
            // With no meeting left to show, the child's page — this one — is
            // already the right place.
            meetingBeingShown = meeting
        case nil:
            break
        }
    }
}

// MARK: - Sheets

private struct StudentWatchingSheets: ViewModifier {
    @Binding var noteBeingEdited: CDNote?
    @Binding var todoBeingEdited: CDTodoItem?
    @Binding var meetingBeingShown: CDStudentMeeting?

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .sheet(item: $noteBeingEdited) { note in
                NoteEditSheet(note: note)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            #endif
            .sheet(item: $todoBeingEdited) { todo in
                NavigationStack {
                    EditTodoForm(todo: todo)
                        .navigationTitle("Edit Todo")
                        .inlineNavigationTitle()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { todoBeingEdited = nil }
                            }
                        }
                }
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #else
                .frame(minWidth: 420, minHeight: 480)
                #endif
            }
            .sheet(item: $meetingBeingShown) { meeting in
                MeetingDetailSheet(meeting: meeting)
            }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct StudentWatchingSectionPreview: View {
    var body: some View {
        Text("StudentWatchingSection requires real data")
    }
}

#Preview {
    StudentWatchingSectionPreview()
}
