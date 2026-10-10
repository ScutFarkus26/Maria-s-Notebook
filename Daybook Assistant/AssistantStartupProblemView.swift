import SwiftUI

/// "Can't start": what went wrong, in the Assistant's words, and the one
/// way out that always works (rebuilding the class from iCloud).
struct AssistantStartupProblemView: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    let problem: AssistantStartupProblem
    @State private var confirmingRebuild = false

    var body: some View {
        ContentUnavailableView {
            Label("Can't start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(problem.message)
        } actions: {
            if problem.canRebuild {
                Button("Download from iCloud again") { confirmingRebuild = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .confirmationDialog(
            "Download your class from iCloud again?",
            isPresented: $confirmingRebuild,
            titleVisibility: .visible
        ) {
            Button("Download again", role: .destructive) {
                Task { await bootstrapper.rebuildFromICloud() }
            }
        } message: {
            Text("The class and every mark already sent come back from iCloud. "
                + "Marks this iPhone hadn't sent yet are lost.")
        }
    }
}
