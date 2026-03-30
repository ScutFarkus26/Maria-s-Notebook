// TodayViewSheets.swift
// Sheet presentations for TodayView - extracted for maintainability

import SwiftUI
import SwiftData

// MARK: - TodayView Sheets Extension

extension TodayView {

    /// All sheet modifiers consolidated into a single view modifier chain.
    @ViewBuilder
    func applySheets<Content: View>(to content: Content) -> some View {
        applySecondarySheets(
            to: content
                .sheet(id: $selectedWorkID) { id in
                    WorkDetailView(workID: id) {
                        selectedWorkID = nil
                        viewModel.reload()
                    }
                }
                .sheet(item: $selectedLessonAssignment) { la in
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
                .sheet(isPresented: $isShowingQuickNote) {
                    QuickNoteSheet()
                }
        )
    }

    @ViewBuilder
    private func applySecondarySheets<Content: View>(to content: Content) -> some View {
        applyDetailSheets(
            to: content
#if os(iOS)
                .sheet(item: $selectedTodoItem) { todo in
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
                .sheet(isPresented: $isShowingNewTodo) {
                    NavigationStack {
                        NewTodoForm()
                            .navigationTitle("New Todo")
                            .inlineNavigationTitle()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") {
                                        isShowingNewTodo = false
                                    }
                                }
                            }
                    }
                }
        )
    }

    @ViewBuilder
    private func applyDetailSheets<Content: View>(to content: Content) -> some View {
        content
            .sheet(item: $noteBeingEdited) { note in
                NoteEditSheet(note: note) {
                    viewModel.reload()
                }
#if os(macOS)
                .frame(minWidth: 520, minHeight: 420)
                .presentationSizingFitted()
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
#endif
            }
            .sheet(id: $selectedMeetingStudentID) { studentID in
                ScheduledMeetingSessionSheet(studentID: studentID) {
                    if let meetingID = selectedMeetingID {
                        MeetingScheduler.clearMeeting(id: meetingID, context: modelContext)
                    }
                    selectedMeetingStudentID = nil
                    selectedMeetingID = nil
                    viewModel.reload()
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
}
