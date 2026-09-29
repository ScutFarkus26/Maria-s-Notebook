import SwiftUI

/// Chooses between onboarding and the attendance list, based on whether this
/// device has joined a classroom.
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
                AssistantAttendanceView(coreDataStack: stack)
            } else {
                AssistantOnboardingView()
            }

        case .failed(let problem):
            AssistantStartupProblemView(problem: problem)
        }
    }
}
