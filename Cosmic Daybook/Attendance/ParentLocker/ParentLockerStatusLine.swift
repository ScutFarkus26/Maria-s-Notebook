import SwiftUI

/// The one ParentLocker line both apps show on the attendance screen ("Sent
/// to ParentLocker 8:47 AM by Sarah · up to date"), with a line under it for
/// each child the sync left alone and why. Shows nothing when ParentLocker
/// isn't how attendance goes.
struct ParentLockerStatusLine: View {

    let status: ParentLockerStatus
    /// The day's send as `AttendanceEmailLog.Send.summary` words it, for the
    /// viewer; nil before the day is sent.
    let sentSummary: String?
    /// The per-child lines; a compact row leaves them out.
    var showsProblems = true

    var body: some View {
        if let line = status.line(sentSummary: sentSummary) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(line)
                } icon: {
                    Image(systemName: symbol)
                }
                .foregroundStyle(status.isTrouble ? Color.orange : Color.secondary)
                if showsProblems {
                    ForEach(status.problems, id: \.self) { problem in
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    private var symbol: String {
        switch status.state {
        case .sending: "arrow.up.circle"
        case .upToDate: "checkmark.circle"
        case .signedOut: "person.crop.circle.badge.questionmark"
        case .previewed: "eye"
        default: status.isTrouble ? "exclamationmark.triangle" : "paperplane"
        }
    }
}

#Preview {
    ParentLockerStatusLinePreview()
}

private struct ParentLockerStatusLinePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ParentLockerStatusLine(
                status: ParentLockerStatus(state: .upToDate), sentSummary: "Sent to ParentLocker 8:47 AM by Sarah"
            )
            ParentLockerStatusLine(
                status: ParentLockerStatus(
                    state: .upToDate,
                    problems: ["The office already marked Maya S Absent."]
                ),
                sentSummary: "Sent to ParentLocker 8:47 AM by you"
            )
            ParentLockerStatusLine(status: ParentLockerStatus(state: .retrying), sentSummary: nil)
        }
        .padding()
    }
}
