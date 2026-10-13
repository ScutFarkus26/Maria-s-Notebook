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
/// Front Desk is (it signs in first on an iPhone that isn't).
struct AssistantParentLockerRow: View {
    let status: ParentLockerStatus
    /// The day's send as `AttendanceEmailLog.Send.summary` words it; nil
    /// before anyone has sent the day.
    let sentSummary: String?
    let isSignedIn: Bool
    let isSending: Bool
    /// Everyone's marked and nobody has sent the day: offer the send.
    var offersSend = false
    let onSendNow: () -> Void
    let onSignIn: () -> Void

    /// Shown when the status has nothing to say yet: a past day not sent, or
    /// today between arrival closing and the send.
    static let notSentLine = "Not sent to ParentLocker yet"

    var body: some View {
        VStack(spacing: 4) {
            if offersSend {
                Button(action: isSignedIn ? onSendNow : onSignIn) {
                    Label("Send to ParentLocker", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(isSending)
                .accessibilityHint(
                    isSignedIn ? "Sends the day's attendance to ParentLocker" : "Opens Sign In to ParentLocker"
                )
            }
            if !offersSend || status.line(sentSummary: sentSummary) != nil {
                statusMenu
            }
        }
        .transition(.opacity)
    }

    private var statusMenu: some View {
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
