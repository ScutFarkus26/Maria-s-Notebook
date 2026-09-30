import SwiftUI

/// The front-desk email's line in the bottom bar.
///
/// The front desk needs the day's attendance by the guide's due time (9:00
/// unless the guide changes it). Until it goes:
/// - once everyone's marked, **Email the Front Desk**;
/// - from half an hour before the due time, even with children still
///   unmarked, **Close Arrival & Email**, which marks them absent (after
///   asking, naming them) and opens the email in one step, with "Due 9:00 AM"
///   beside it;
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
    private var deadlineMinutes: Int {
        frontDesk.settings?.deadlineMinutes ?? AttendanceEmailLog.defaultDeadlineMinutes
    }

    var body: some View {
        if frontDesk.isOffered(by: viewModel) {
            // Redrawn only at the two moments the line changes: half an hour
            // before the due time, and at it. The clock is read, not the
            // entry's date: before the first entry an explicit timeline
            // hands the view that first entry, not now.
            TimelineView(.explicit(changeTimes)) { _ in
                content(urgency: AttendanceEmailLog.urgency(for: viewModel.date, deadlineMinutes: deadlineMinutes))
            }
            .animation(.smooth(duration: 0.3), value: frontDesk.latestSend)
        }
    }

    private var changeTimes: [Date] {
        let calendar = Calendar.current
        guard let deadline = calendar.date(
            byAdding: .minute, value: deadlineMinutes, to: calendar.startOfDay(for: viewModel.date)
        ) else { return [] }
        return [deadline.addingTimeInterval(-Double(AttendanceEmailLog.dueWindowMinutes) * 60), deadline]
    }

    @ViewBuilder
    private func content(urgency: AttendanceEmailLog.Urgency) -> some View {
        VStack(spacing: 4) {
            if let send = frontDesk.latestSend {
                sentLine(send)
            } else if viewModel.unmarkedCount == 0 {
                sendButton("Email the Front Desk", urgency: urgency, action: onSend)
                dueLine(urgency)
            } else if urgency != .none, viewModel.canMark, viewModel.phase == .arrival {
                sendButton("Close Arrival & Email", urgency: urgency, action: onCloseAndSend)
                dueLine(urgency)
            }
            if let error = frontDesk.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
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
        .tint(isOverdue(urgency) ? Color.lateAmber : nil)
        .contextMenu {
            Button("Mark as Sent", systemImage: "checkmark.circle") {
                frontDesk.recordSend(confirmedByHand: true)
            }
        }
        .accessibilityHint("Opens today's attendance email, ready to send. Touch and hold to mark it sent.")
        .transition(.opacity)
    }

    @ViewBuilder
    private func dueLine(_ urgency: AttendanceEmailLog.Urgency) -> some View {
        switch urgency {
        case .none:
            EmptyView()
        case .due(let deadline):
            Text("Due at the front desk by \(deadline.formatted(date: .omitted, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .overdue(let deadline):
            Text("Late: it was due by \(deadline.formatted(date: .omitted, time: .shortened))")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.lateAmber)
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
