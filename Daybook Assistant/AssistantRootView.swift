import SwiftUI

/// Chooses between onboarding and the attendance list, based on whether this
/// device has joined a classroom.
struct AssistantRootView: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    var body: some View {
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

        case .failed(let message):
            ContentUnavailableView {
                Label("Can't start", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        }
    }
}
