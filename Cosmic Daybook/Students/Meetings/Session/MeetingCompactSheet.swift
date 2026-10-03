import SwiftUI
import CoreData

/// On a phone, the header chips open the meeting's context one part at a time.
struct MeetingCompactSheet: View {
    enum Kind: String, Identifiable {
        case decisions, lessons, meetings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .decisions: "Work"
            case .lessons: "Lessons Since Last Meeting"
            case .meetings: "Past Meetings"
            }
        }

        var sections: MeetingContextPane.Sections {
            switch self {
            case .decisions: [.decisions, .openWork]
            case .lessons: [.lessons]
            case .meetings: [.meetings]
            }
        }
    }

    let sheet: Kind
    let sessionWork: MeetingWorkSnapshotHelper.SessionWork
    let lessons: [CDLessonAssignment]
    let meetings: [CDStudentMeeting]
    let lastMeetingDate: Date?
    let draft: MeetingDraftModel
    let names: MeetingCatalogNames
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                pane.padding(16)
            }
            .navigationTitle(sheet.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var pane: some View {
        MeetingContextPane(
            stuckWork: sessionWork.stuck,
            openWork: sessionWork.open,
            lessonsSince: lessons,
            meetings: meetings,
            lastMeetingDate: lastMeetingDate,
            draft: draft,
            workTitle: names.workTitle,
            lessonName: names.lessonName,
            lessonArea: { names.lesson(for: $0)?.area },
            sections: sheet.sections
        )
    }
}
