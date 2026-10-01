import SwiftUI

/// Shown until the guide's invitation has been accepted on this device.
///
/// Four pages, swiped or stepped through with Continue: Welcome, a practice
/// grid that marks the way the real one does, an iCloud check, and the
/// invitation page, which is where this screen rests. There is nothing to
/// configure for joining: it happens by opening the link the guide sends,
/// which iOS routes to this app. So the invitation page says that plainly,
/// shows the join while it's under way, and names the two things that
/// commonly go wrong: iCloud not being available, and a join that failed.
///
/// Once she has reached the invitation page, a relaunch opens on it, with
/// the intro a swipe back (`AssistantOnboarding.introSeen`). Opening the link
/// from any page jumps there to show the join.
struct AssistantOnboardingView: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    enum Page: Hashable {
        case welcome, practice, iCloud, invitation
    }

    @State private var page: Page = AssistantOnboarding.introSeen() ? .invitation : .welcome

    private var isJoining: Bool { bootstrapper.sharingService?.isJoining ?? false }
    private var joinError: String? { bootstrapper.sharingService?.shareError }

    var body: some View {
        TabView(selection: $page) {
            AssistantWelcomePage(onStart: { go(to: .practice) })
                .tag(Page.welcome)
            AssistantPracticePage(onContinue: { go(to: .iCloud) })
                .tag(Page.practice)
            AssistantICloudPage(onContinue: { go(to: .invitation) })
                .tag(Page.iCloud)
            AssistantInvitationPage()
                .tag(Page.invitation)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: page) { _, page in
            if page == .invitation { AssistantOnboarding.markIntroSeen() }
        }
        // The link was opened, or a join failed, while she was on another
        // page: the invitation page is where both show.
        .onChange(of: isJoining) { _, joining in
            if joining { go(to: .invitation) }
        }
        .onChange(of: joinError) { _, error in
            if error != nil { go(to: .invitation) }
        }
        .onAppear {
            if isJoining || joinError != nil { page = .invitation }
        }
    }

    private func go(to next: Page) {
        withAnimation(.smooth) { page = next }
    }
}
