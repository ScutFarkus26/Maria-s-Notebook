import SwiftUI

/// The Classroom sheet's ParentLocker row, once the guide has picked
/// ParentLocker: her own sign-in, made once on this iPhone with her own
/// ParentLocker account (`ParentLockerSignInSheet`, which also has Sign Out).
/// The footer says what it's for, or what ParentLocker needs from her.
struct AssistantParentLockerSection: View {
    let sync: ParentLockerSync

    @State private var showingSignIn = false

    static let signedOutFooter = "Your guide sends attendance to ParentLocker. Sign in once with your own "
        + "ParentLocker account, and Close Arrival & Send sends it from this iPhone."
    static let signedInFooter = "Close Arrival & Send sends the class to ParentLocker under your account, "
        + "and later changes follow by themselves."

    var body: some View {
        Section {
            Button {
                showingSignIn = true
            } label: {
                LabeledContent("ParentLocker") {
                    Text(Self.signInLabel(isSignedIn: sync.isSignedIn, needsSignIn: sync.needsSignIn))
                        .foregroundStyle(sync.needsSignIn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
            .foregroundStyle(.primary)
            .accessibilityHint(sync.needsSignIn ? "Opens Sign In to ParentLocker" : "Opens Sign Out")
        } footer: {
            if let trouble = troubleLine {
                Text(trouble).foregroundStyle(.orange)
            } else {
                Text(sync.needsSignIn ? Self.signedOutFooter : Self.signedInFooter)
            }
        }
        .sheet(isPresented: $showingSignIn, onDismiss: {
            // Closed without signing in: a send waiting for it doesn't ask
            // again by itself, and a Send Now waiting for it is dropped.
            if sync.needsSignIn { sync.signInDismissed() }
        }, content: {
            ParentLockerSignInSheet(sync: sync)
        })
    }

    /// The row's value. A password ParentLocker refused isn't a sign-in
    /// that works, so it says to sign in again (bug hunt 2026-10-13
    /// afternoon, L4), as the menus offer Sign In then.
    static func signInLabel(isSignedIn: Bool, needsSignIn: Bool) -> String {
        guard needsSignIn else { return "Signed in" }
        return isSignedIn ? "Sign in again" : "Not signed in"
    }

    /// What only she can fix: a password ParentLocker no longer takes, or
    /// something ParentLocker wants her to do.
    private var troubleLine: String? {
        switch sync.status.state {
        case .passwordRefused, .needsYou, .keychainTrouble: sync.status.message
        default: nil
        }
    }
}
