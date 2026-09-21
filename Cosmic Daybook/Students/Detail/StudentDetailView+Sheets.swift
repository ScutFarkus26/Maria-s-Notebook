import SwiftUI

// MARK: - Sheet Types & Content

extension StudentDetailView {

    /// The one sheet the record can show at a time. The delete alert, the
    /// view model's give-lesson and presentation-detail items, and the work
    /// selection (a sheet on iOS, a window on macOS) keep their own state.
    enum ActiveSheet: Identifiable {
        case aiPlanning
        case quickNote
        #if os(iOS)
        case documents
        case meetingSession
        #endif

        var id: String {
            switch self {
            case .aiPlanning: return "aiPlanning"
            case .quickNote: return "quickNote"
            #if os(iOS)
            case .documents: return "documents"
            case .meetingSession: return "meetingSession"
            #endif
            }
        }
    }

    @ViewBuilder
    func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .aiPlanning:
            AIPlanningAssistantView(mode: .singleStudent(student.id ?? UUID()))
        case .quickNote:
            QuickNoteSheet(initialStudentID: student.id)
        #if os(iOS)
        case .documents:
            NavigationStack {
                StudentFilesTab(student: student)
                    .navigationTitle("Documents")
            }
        case .meetingSession:
            if let studentID = student.id {
                ScheduledMeetingSessionSheet(studentID: studentID)
            }
        #endif
        }
    }
}
