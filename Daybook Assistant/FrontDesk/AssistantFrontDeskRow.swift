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
/// day off or a day ahead. When the guide picked ParentLocker instead, the
/// ParentLocker line takes its place (`AssistantParentLockerRow`), with Send
/// Now for the day on screen.
struct AssistantFrontDeskRow: View {
    let viewModel: AssistantAttendanceViewModel
    let onSend: () -> Void
    /// Close arrival (asking first), then open the email.
    let onCloseAndSend: () -> Void
    /// Opens the ParentLocker sign-in, which the bar holds (one sheet for
    /// its Close Arrival & Send and this line).
    var onParentLockerSignIn: () -> Void = {}
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    /// Bumped at the moments the line changes, to redraw it then.
    @State private var changes = 0
    @State private var isSendingNow = false
    /// Send Now with children unmarked: who, for the question (M4).
    @State private var unmarkedToAsk: [String] = []
    /// What another day's Send Now came to, when it didn't go (L1).
    @State private var sendNowMessage: (day: Date, text: String)?

    private var frontDesk: AssistantFrontDesk { viewModel.frontDesk }
    private var deadlineMinutes: Int { frontDesk.deadlineMinutes }

    /// Due, late or neither, by the clock now.
    private var urgency: AttendanceEmailLog.Urgency {
        _ = changes
        return AttendanceEmailLog.urgency(for: viewModel.date, deadlineMinutes: deadlineMinutes)
    }

    var body: some View {
        if frontDesk.offersParentLocker(by: viewModel), let sync = bootstrapper.parentLockerForScreens {
            parentLockerRow(sync)
        } else if frontDesk.isOffered(by: viewModel) {
            content(urgency: urgency)
                .animation(.smooth(duration: 0.3), value: frontDesk.latestSend)
                // Redrawn only at the two moments the line changes: half an
                // hour before the due time, and at it. Not an explicit
                // TimelineView: once both moments had passed (every day after
                // the due time, and every past day) it redrew the bar every
                // frame, 8–10% CPU on an idle grid (2026-10-10).
                .task(id: frontDesk.changeTimes(on: viewModel.date)) {
                    for time in Self.changesAhead(frontDesk.changeTimes(on: viewModel.date), now: Date()) {
                        guard (try? await Task.sleep(for: .seconds(time.timeIntervalSinceNow))) != nil else { return }
                        changes += 1
                    }
                }
        }
    }

    /// The change moments still ahead of `now`: none once the due time has
    /// passed, so the line then waits for nothing.
    static func changesAhead(_ times: [Date], now: Date) -> [Date] {
        times.filter { $0 > now }
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

    /// "Emailed 8:42 AM by Sarah", "Sent to ParentLocker 8:47 AM by you".
    private func summary(of send: AttendanceEmailLog.Send) -> String {
        let name = send.senderName(
            viewerRole: .assistant,
            myRecordName: ClassroomIdentity.currentUserRecordName,
            myName: ClassroomIdentity.displayName,
            guideName: bootstrapper.guideName,
            names: viewModel.names
        )
        return send.summary(senderName: name, for: viewModel.date, deadlineMinutes: deadlineMinutes)
    }

    private func sentLine(_ send: AttendanceEmailLog.Send) -> some View {
        let summary = summary(of: send)
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

// MARK: - ParentLocker

extension AssistantFrontDeskRow {

    /// The status line and Send Now. The engine's status is today's, so
    /// another day shows only whether it was sent, and what its Send Now
    /// came to when it didn't go.
    fileprivate func parentLockerRow(_ sync: ParentLockerSync) -> some View {
        AssistantParentLockerRow(
            status: viewModel.isToday ? sync.status : ParentLockerStatus(state: .idle),
            sentSummary: frontDesk.latestSend.map(summary(of:)),
            isSignedIn: !sync.needsSignIn,
            isSending: isSendingNow || sync.status.state == .sending,
            offersSend: frontDesk.offersParentLockerSend(by: viewModel),
            sendNowMessage: sendNowMessage.flatMap {
                Calendar.current.isDate($0.day, inSameDayAs: viewModel.date) ? $0.text : nil
            },
            onSendNow: { sendNow(sync, unmarkedConfirmed: false) },
            onSignIn: onParentLockerSignIn
        )
        .animation(.smooth(duration: 0.3), value: frontDesk.latestSend)
        // The sync records the day's send itself: the line reads it again
        // after each run that reached ParentLocker.
        .onChange(of: sync.status.lastSyncAt) { frontDesk.load(viewModel.date) }
        .confirmationDialog(
            AssistantParentLockerSendStep.question(unmarked: unmarkedToAsk),
            isPresented: Binding(get: { !unmarkedToAsk.isEmpty }, set: { if !$0 { unmarkedToAsk = [] } }),
            titleVisibility: .visible
        ) {
            Button("Send the Others") { sendNow(sync, unmarkedConfirmed: true) }
        } message: {
            Text(AssistantParentLockerSendStep.questionMessage(unmarked: unmarkedToAsk))
        }
    }

    /// Send Now (and Send to ParentLocker): the whole class for the day on
    /// screen. With children unmarked it asks first, naming them (bug hunt
    /// 2026-10-13 afternoon, M4). Not signed in, today's send waits for the
    /// sign-in, which opens in the same tap (L6); another day's only opens it.
    fileprivate func sendNow(_ sync: ParentLockerSync, unmarkedConfirmed: Bool) {
        let day = viewModel.date
        let isToday = viewModel.isToday
        switch AssistantParentLockerSendStep.first(
            on: day, isToday: isToday, unmarkedConfirmed: unmarkedConfirmed, sync: sync
        ) {
        case .ask(let unmarked):
            unmarkedToAsk = unmarked
            return
        case .signIn:
            onParentLockerSignIn()
            return
        case .sendAfterSignIn:
            onParentLockerSignIn()
        case .send:
            break
        }
        sendNowMessage = nil
        isSendingNow = true
        Task {
            let status = await sync.sendNow(day: day)
            isSendingNow = false
            // The line is today's: another day's Send Now says here how it went.
            if !isToday, let text = AssistantParentLockerRow.pastDayMessage(after: status) {
                sendNowMessage = (day, text)
            }
            // The day on screen now, which she may have stepped away from.
            frontDesk.load(viewModel.date)
        }
    }
}
