import SwiftUI

/// Shown until the guide's invitation has been accepted on this device.
///
/// There is nothing to configure here — joining happens by opening the link the
/// guide sends, which iOS routes to this app. So the screen says that plainly,
/// shows the join while it's under way, and names the two things that commonly
/// go wrong: iCloud not being available, and a join that failed.
struct AssistantOnboardingView: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    private var isJoining: Bool { bootstrapper.sharingService?.isJoining ?? false }
    private var joinError: String? { bootstrapper.sharingService?.shareError }
    private var iCloudProblem: String? { bootstrapper.accountStatus?.assistantProblem }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.2.badge.key")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            if isJoining {
                joining
            } else {
                instructions
            }

            Spacer()

            if !isJoining {
                Button("Check Again") {
                    bootstrapper.refreshMembership()
                    Task { await bootstrapper.refreshAccountStatus() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .animation(.smooth, value: isJoining)
    }

    private var joining: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Joining your classroom…")
                .font(.title3.weight(.semibold))
            Text("This can take a minute. Keep the app open.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var instructions: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Join a Classroom")
                    .font(.title2.weight(.semibold))

                Text("Your guide will send you an invitation link. "
                    + "Open it on this iPhone and it will bring you straight back here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let joinError {
                problem(
                    "\(joinError) Ask your guide to send the invitation again, then open it here.",
                    systemImage: "exclamationmark.triangle"
                )
            } else if let iCloudProblem {
                problem(iCloudProblem, systemImage: "icloud.slash")
            }

            VStack(alignment: .leading, spacing: 12) {
                if iCloudProblem == nil {
                    Label("Make sure you're signed in to iCloud in Settings", systemImage: "icloud")
                }
                Label("Open the guide's link from Messages or Mail", systemImage: "link")
                Label("The class list appears here once you've joined", systemImage: "checklist")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func problem(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
