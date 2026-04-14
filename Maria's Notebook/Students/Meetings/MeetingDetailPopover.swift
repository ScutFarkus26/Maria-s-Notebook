import SwiftUI

struct MeetingDetailPopover: View {
    let meeting: CDStudentMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text((meeting.date ?? Date()).formatted(date: .long, time: .omitted))
                    .font(.headline)

                if meeting.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                }

                Spacer()
            }

            Divider()

            if !meeting.reflection.trimmed().isEmpty {
                DetailLine(title: "Reflection", text: meeting.reflection)
            }

            if !meeting.focus.trimmed().isEmpty {
                DetailLine(title: "Focus", text: meeting.focus)
            }

            if !meeting.requests.trimmed().isEmpty {
                DetailLine(title: "Requests", text: meeting.requests)
            }

            if !meeting.guideNotes.trimmed().isEmpty {
                DetailLine(title: "Guide Notes", text: meeting.guideNotes)
            }

            if meeting.reflection.trimmed().isEmpty
                && meeting.focus.trimmed().isEmpty
                && meeting.requests.trimmed().isEmpty
                && meeting.guideNotes.trimmed().isEmpty {
                Text("No notes recorded")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 280, maxWidth: 360)
    }
}
