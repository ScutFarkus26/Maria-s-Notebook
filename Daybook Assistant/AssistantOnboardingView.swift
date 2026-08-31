import SwiftUI

/// Shown until the guide's invitation has been accepted on this device.
///
/// There is nothing to configure here — joining happens by opening the link the
/// guide sends, which iOS routes to this app. So the screen's whole job is to
/// say that plainly and to surface the one thing that commonly goes wrong,
/// which is not being signed in to iCloud.
struct AssistantOnboardingView: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.2.badge.key")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text("Join a Classroom")
                    .font(.title2.weight(.semibold))

                Text("Your guide will send you an invitation link. Open it on this iPhone and it will bring you straight back here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Make sure you're signed in to iCloud in Settings", systemImage: "icloud")
                Label("Open the guide's link from Messages or Mail", systemImage: "link")
                Label("The class list appears here once you've joined", systemImage: "checklist")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button("Check Again") {
                bootstrapper.refreshMembership()
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
    }
}
