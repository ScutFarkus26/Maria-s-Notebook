import SwiftUI
import CoreData

// MARK: - Sheet Types

extension TodayView {

    /// The sheets Today opens the same way on both platforms. The work,
    /// presentation, note, meeting, and todo selections keep their own state:
    /// on iOS each is a sheet, on macOS the same value opens a window (or,
    /// for a todo, fills the right column).
    enum ActiveSheet: Identifiable {
        case quickNote(studentIDs: Set<UUID>?)
        case newTodo

        var id: String {
            switch self {
            case .quickNote: return "quickNote"
            case .newTodo: return "newTodo"
            }
        }
    }
}

// MARK: - Sheets Modifier
// Bundles all of TodayView's sheet presentations into a single ViewModifier so
// the body's modifier chain stays short enough for the type checker.
struct TodayViewSheets: ViewModifier {
    @Binding var selectedWorkID: UUID?
    @Binding var selectedLessonAssignment: CDLessonAssignment?
    @Binding var activeSheet: TodayView.ActiveSheet?
    @Binding var selectedTodoItem: CDTodoItem?
    @Binding var noteBeingEdited: CDNote?
    @Binding var selectedMeetingStudentID: UUID?
    @Binding var selectedMeetingID: UUID?
    let viewContext: NSManagedObjectContext
    let onReload: () -> Void

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .sheet(id: $selectedWorkID) { id in
                WorkDetailView(workID: id) {
                    selectedWorkID = nil
                    onReload()
                }
            }
            #endif
            #if os(iOS)
                .sheet(item: $selectedLessonAssignment) { la in
                    lessonAssignmentSheet(la)
                }
            #endif
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
#if os(iOS)
            .sheet(item: $selectedTodoItem) { todo in
                editTodoSheet(todo)
            }
#endif
            #if os(iOS)
            .sheet(item: $noteBeingEdited) { note in
                noteEditSheet(note)
            }
            #endif
            #if os(iOS)
            .sheet(id: $selectedMeetingStudentID) { studentID in
                meetingSessionSheet(studentID)
            }
            #endif
    }

    @ViewBuilder
    private func sheetContent(for sheet: TodayView.ActiveSheet) -> some View {
        switch sheet {
        case .quickNote(let studentIDs):
            quickNoteSheetContent(studentIDs: studentIDs)
        case .newTodo:
            newTodoSheet
        }
    }

    private func lessonAssignmentSheet(_ la: CDLessonAssignment) -> some View {
        PresentationDetailView(lessonAssignment: la) {
            selectedLessonAssignment = nil
        }
#if os(macOS)
        .frame(minWidth: 720, minHeight: 640)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }

    @ViewBuilder
    private func quickNoteSheetContent(studentIDs: Set<UUID>?) -> some View {
        if let preselected = studentIDs {
            QuickNoteSheet(initialStudentIDs: preselected)
        } else {
            QuickNoteSheet()
        }
    }

#if os(iOS)
    private func editTodoSheet(_ todo: CDTodoItem) -> some View {
        NavigationStack {
            EditTodoForm(todo: todo)
                .navigationTitle("Edit Todo")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            selectedTodoItem = nil
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
#endif

    private var newTodoSheet: some View {
        NavigationStack {
            NewTodoForm()
                .navigationTitle("New Todo")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            activeSheet = nil
                        }
                    }
                }
        }
    }

    private func noteEditSheet(_ note: CDNote) -> some View {
        NoteEditSheet(note: note) {
            onReload()
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }

    private func meetingSessionSheet(_ studentID: UUID) -> some View {
        ScheduledMeetingSessionSheet(studentID: studentID) {
            if let meetingID = selectedMeetingID {
                MeetingScheduler.clearMeeting(id: meetingID, context: viewContext)
            }
            selectedMeetingStudentID = nil
            selectedMeetingID = nil
            onReload()
        }
#if os(macOS)
        .frame(minWidth: 860, minHeight: 640)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }
}
