import SwiftUI

/// Chooses between onboarding and the app's tabs (Attendance and Restock),
/// based on whether this device has joined a classroom.
struct AssistantRootView: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    var body: some View {
        content
            // The shared sharing and save code report failures through
            // `ToastService`; this is where the Assistant shows them.
            .overlay(alignment: .top) {
                if let toast = ToastService.shared.current {
                    Label(toast.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                        // It only says something: taps go through to the
                        // date and buttons under it.
                        .allowsHitTesting(false)
                }
            }
            .animation(.smooth, value: ToastService.shared.current?.id)
    }

    @ViewBuilder
    private var content: some View {
        switch bootstrapper.phase {
        case .starting:
            ProgressView("Starting…")

        case .needsClassroom:
            AssistantOnboardingView()

        case .ready:
            if let stack = bootstrapper.coreDataStack {
                // A rebuilt stack is a new screen: its view models must not
                // keep reading the old stack's context.
                AssistantTabs(coreDataStack: stack)
                    .id(ObjectIdentifier(stack))
            } else {
                AssistantOnboardingView()
            }

        case .failed(let problem):
            AssistantStartupProblemView(problem: problem)
        }
    }
}
