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
/// the intro a swipe back (`AssistantOnboarding.introSeen`, `startPage`). Opening the link
/// from any page jumps there to show the join.
///
/// The page is kept for the scene, not the view: a stack rebuilt after an
/// iCloud sign-in can swap this screen out and back, and it used to come
/// back on Welcome (bug hunt 2026-10-20 #22).
struct AssistantOnboardingView: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    enum Page: String, Hashable {
        case welcome, practice, iCloud, invitation
    }

    @SceneStorage("Assistant.onboarding.page")
    private var page: Page = AssistantOnboarding.introSeen() ? .invitation : .welcome

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
            let first = !Self.shownThisLaunch
            Self.shownThisLaunch = true
            page = Self.startPage(restored: page, introSeen: AssistantOnboarding.introSeen(), firstThisLaunch: first)
            if isJoining || joinError != nil { page = .invitation }
        }
    }

    /// Whether this screen has shown since launch: scene storage keeps the
    /// page across a relaunch too, which only a swap should keep.
    private static var shownThisLaunch = false

    /// The page to open on: the invitation page on the first showing after a
    /// launch once she has reached it, as the doc comment says, even when
    /// scene storage kept another; later in the launch, the page she was on
    /// (review (d), #5).
    static func startPage(restored: Page, introSeen: Bool, firstThisLaunch: Bool) -> Page {
        firstThisLaunch && introSeen ? .invitation : restored
    }

    private func go(to next: Page) {
        withAnimation(.smooth) { page = next }
    }
}
