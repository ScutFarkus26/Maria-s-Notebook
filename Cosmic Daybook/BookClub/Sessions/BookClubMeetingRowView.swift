import SwiftUI

struct BookClubMeetingRowView: View {
    @ObservedObject var meeting: CDBookClubMeeting
    let leaderName: String?
    var onToggleCompleted: () -> Void
    var onReassignLeader: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleCompleted) {
                Image(systemName: meeting.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(meeting.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(meeting.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Meeting \(meeting.ordinal)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let date = meeting.date {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(meeting.readingLabel.isEmpty ? "(No reading set)" : meeting.readingLabel)
                    .font(.body)
                    .foregroundStyle(meeting.readingLabel.isEmpty ? .secondary : .primary)
                    .lineLimit(2)

                Button(action: onReassignLeader) {
                    HStack(spacing: 4) {
                        Image(systemName: "person")
                            .font(.caption)
                        Text(leaderName ?? "Assign leader")
                            .font(.caption)
                    }
                    .foregroundStyle(leaderName == nil ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .opacity(meeting.isCompleted ? 0.65 : 1.0)
    }
}
