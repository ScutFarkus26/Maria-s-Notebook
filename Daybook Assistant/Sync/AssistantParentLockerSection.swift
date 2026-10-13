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
                    Text(sync.isSignedIn ? "Signed in" : "Not signed in")
                        .foregroundStyle(sync.isSignedIn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
            }
            .foregroundStyle(.primary)
            .accessibilityHint(sync.isSignedIn ? "Opens Sign Out" : "Opens Sign In to ParentLocker")
        } footer: {
            if let trouble = troubleLine {
                Text(trouble).foregroundStyle(.orange)
            } else {
                Text(sync.isSignedIn ? Self.signedInFooter : Self.signedOutFooter)
            }
        }
        .sheet(isPresented: $showingSignIn) {
            ParentLockerSignInSheet(sync: sync)
        }
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
