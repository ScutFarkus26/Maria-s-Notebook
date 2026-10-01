import SwiftUI

/// The front-desk email's line in the bottom bar.
///
/// The front desk needs the day's attendance by the guide's due time (9:00
/// unless the guide changes it). Until it goes:
/// - once everyone's marked, **Email the Front Desk**;
/// - from half an hour before the due time, even with children still
///   unmarked, **Close Arrival & Email**, which marks them absent (after
///   asking, naming them) and opens the email in one step, with "Due 9:00 AM"
///   beside it (a small button, so the grid keeps its room);
/// - after the due time, the same in amber, saying it's late.
///
/// Once anyone has sent it (here, on another assistant's phone or the
/// guide's), who sent it and when, marked "(late)" after the due time, with
/// Send Again.
///
/// Only when the guide has set the email up in the notebook, and never on a
/// day off or a day ahead.
struct AssistantFrontDeskRow: View {
    let viewModel: AssistantAttendanceViewModel
    let onSend: () -> Void
    /// Close arrival (asking first), then open the email.
    let onCloseAndSend: () -> Void
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    private var frontDesk: AssistantFrontDesk { viewModel.frontDesk }
    private var deadlineMinutes: Int { frontDesk.deadlineMinutes }

    var body: some View {
        if frontDesk.isOffered(by: viewModel) {
            // Redrawn only at the two moments the line changes: half an hour
            // before the due time, and at it. The clock is read, not the
            // entry's date: before the first entry an explicit timeline
            // hands the view that first entry, not now.
            TimelineView(.explicit(frontDesk.changeTimes(on: viewModel.date))) { _ in
                content(urgency: AttendanceEmailLog.urgency(for: viewModel.date, deadlineMinutes: deadlineMinutes))
            }
            .animation(.smooth(duration: 0.3), value: frontDesk.latestSend)
        }
    }

    @ViewBuilder
    private func content(urgency: AttendanceEmailLog.Urgency) -> some View {
        VStack(spacing: 4) {
            if let send = frontDesk.latestSend {
                sentLine(send)
            } else if viewModel.unmarkedCount == 0 {
                buttonAndDueLine("Email the Front Desk", urgency: urgency, action: onSend)
            } else if frontDesk.offersCloseAndEmail(by: viewModel) {
                buttonAndDueLine("Close Arrival & Email", urgency: urgency, action: onCloseAndSend)
            }
            if let error = frontDesk.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// A small button with the due time beside it, so the bar takes no more
    /// room than it must and the grid's last row stays in sight on an SE;
    /// stacked when the text is too large for one line.
    private func buttonAndDueLine(
        _ title: String, urgency: AttendanceEmailLog.Urgency, action: @escaping () -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                sendButton(title, urgency: urgency, action: action)
                dueLine(urgency, short: true)
            }
            VStack(spacing: 4) {
                sendButton(title, urgency: urgency, action: action)
                dueLine(urgency, short: false)
            }
        }
    }

    private func sendButton(
        _ title: String, urgency: AttendanceEmailLog.Urgency, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: "envelope.fill")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(isOverdue(urgency) ? Color.lateAmber : nil)
        .contextMenu {
            Button("Mark as Sent", systemImage: "checkmark.circle") {
                frontDesk.recordSend(confirmedByHand: true)
            }
        }
        .accessibilityHint("Opens today's attendance email, ready to send. Touch and hold to mark it sent.")
        .transition(.opacity)
    }

    /// When it's due, or that it's late. `short` is the version beside the
    /// button ("Due 9:00 AM", "Late · due 9:00 AM").
    @ViewBuilder
    private func dueLine(_ urgency: AttendanceEmailLog.Urgency, short: Bool) -> some View {
        switch urgency {
        case .none:
            EmptyView()
        case .due(let deadline):
            let time = deadline.formatted(date: .omitted, time: .shortened)
            Text(short ? "Due \(time)" : "Due at the front desk by \(time)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize()
        case .overdue(let deadline):
            let time = deadline.formatted(date: .omitted, time: .shortened)
            Text(short ? "Late · due \(time)" : "Late: it was due by \(time)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.lateAmber)
                .fixedSize()
        }
    }

    private func isOverdue(_ urgency: AttendanceEmailLog.Urgency) -> Bool {
        if case .overdue = urgency { return true }
        return false
    }

    private func sentLine(_ send: AttendanceEmailLog.Send) -> some View {
        let name = send.senderName(
            viewerRole: .assistant,
            myRecordName: ClassroomIdentity.currentUserRecordName,
            myName: ClassroomIdentity.displayName,
            guideName: bootstrapper.guideName
        )
        let summary = send.summary(senderName: name, for: viewModel.date, deadlineMinutes: deadlineMinutes)
        return Menu {
            Button("Send Again", systemImage: "envelope", action: onSend)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Front desk: \(summary)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.footnote)
        }
        .accessibilityHint("Opens Send Again")
        .transition(.opacity)
    }
}
