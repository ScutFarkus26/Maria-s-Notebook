import SwiftUI

/// ParentLocker's line in the bottom bar, in the front-desk email's place
/// when the guide picked ParentLocker: the shared status line ("Sent to
/// ParentLocker 8:47 AM by Sarah · up to date"), which opens a menu with
/// Send Now, Sign In when this iPhone isn't signed in, and a line for each
/// child the sync left alone. The words are the engine's
/// (`ParentLockerStatus`), so both apps say the same thing.
///
/// With everyone marked and the day not sent, there's no Close Arrival to
/// send it, so **Send to ParentLocker** is offered instead, as Email the
/// Front Desk is. On an iPhone that isn't signed in, the one tap asks for
/// today's send and opens the sign-in; the send goes once she signs in (bug
/// hunt 2026-10-13 afternoon, L6).
struct AssistantParentLockerRow: View {
    let status: ParentLockerStatus
    /// The day's send as `AttendanceEmailLog.Send.summary` words it; nil
    /// before anyone has sent the day.
    let sentSummary: String?
    let isSignedIn: Bool
    let isSending: Bool
    /// Everyone's marked and nobody has sent the day: offer the send.
    var offersSend = false
    /// What the last Send Now of another day came to, when it didn't go (L1).
    var sendNowMessage: String?
    let onSendNow: () -> Void
    let onSignIn: () -> Void

    /// Shown when the status has nothing to say yet: a past day not sent, or
    /// today between arrival closing and the send.
    static let notSentLine = "Not sent to ParentLocker yet"

    var body: some View {
        let shown = Self.shownStatus(offersSend: offersSend, status: status)
        VStack(spacing: 4) {
            if offersSend {
                Button(action: onSendNow) {
                    Label("Send to ParentLocker", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(isSending)
                .accessibilityHint(
                    isSignedIn
                        ? "Sends the day's attendance to ParentLocker"
                        : "Opens Sign In to ParentLocker, then sends the day's attendance"
                )
            }
            if Self.showsStatusMenu(offersSend: offersSend, status: status, sentSummary: sentSummary) {
                statusMenu(shown)
            }
            if let sendNowMessage {
                Text(sendNowMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .transition(.opacity)
    }

    /// The status the line shows. Beside Send to ParentLocker, "Attendance
    /// goes to ParentLocker when arrival closes" would point at a Close
    /// Arrival that isn't there (everyone's marked), and "Everyone's marked.
    /// Send it to ParentLocker." at the button right above it, so it says
    /// nothing (bug hunt 2026-10-13 afternoon, M2); the children's lines stay.
    static func shownStatus(offersSend: Bool, status: ParentLockerStatus) -> ParentLockerStatus {
        guard offersSend, status.state == .waitingForArrival || status.state == .readyToSend else { return status }
        return ParentLockerStatus(state: .idle, problems: status.problems, lastSyncAt: status.lastSyncAt)
    }

    /// Whether the status line shows: always, except beside Send to
    /// ParentLocker with nothing to say.
    static func showsStatusMenu(offersSend: Bool, status: ParentLockerStatus, sentSummary: String?) -> Bool {
        let shown = shownStatus(offersSend: offersSend, status: status)
        return !offersSend || shown.line(sentSummary: sentSummary) != nil || !shown.problems.isEmpty
    }

    /// What a Send Now of another day says when it didn't go, or found
    /// something it couldn't send (bug hunt 2026-10-13 afternoon, L1): the
    /// line is today's, so without this it said nothing. Nil when it went,
    /// which the line shows ("Sent to ParentLocker 8:47 AM by you").
    static func pastDayMessage(after status: ParentLockerStatus) -> String? {
        switch status.state {
        case .upToDate, .idle, .off, .sending, .waitingForArrival: status.problems.first
        default: status.message ?? status.problems.first
        }
    }

    private func statusMenu(_ status: ParentLockerStatus) -> some View {
        Menu {
            if !status.problems.isEmpty {
                Section {
                    ForEach(status.problems, id: \.self) { Text($0) }
                }
            }
            if isSignedIn {
                Button("Send Now", systemImage: "paperplane", action: onSendNow)
                    .disabled(isSending)
            } else {
                Button("Sign In to ParentLocker…", systemImage: "person.crop.circle", action: onSignIn)
            }
        } label: {
            if status.line(sentSummary: sentSummary) != nil {
                ParentLockerStatusLine(status: status, sentSummary: sentSummary, showsProblems: false)
                    .multilineTextAlignment(.leading)
            } else {
                Label(Self.notSentLine, systemImage: "paperplane")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHint(isSignedIn ? "Opens Send Now" : "Opens Sign In to ParentLocker")
    }
}

#Preview {
    AssistantParentLockerRowPreview()
}

private struct AssistantParentLockerRowPreview: View {
    var body: some View {
        VStack(spacing: 16) {
            AssistantParentLockerRow(
                status: ParentLockerStatus(state: .upToDate), sentSummary: "Sent to ParentLocker 8:47 AM by you",
                isSignedIn: true, isSending: false, onSendNow: {}, onSignIn: {}
            )
            AssistantParentLockerRow(
                status: ParentLockerStatus(state: .signedOut), sentSummary: nil,
                isSignedIn: false, isSending: false, offersSend: true, onSendNow: {}, onSignIn: {}
            )
        }
        .padding()
    }
}
