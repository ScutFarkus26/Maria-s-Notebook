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
            Button("Rebuild from iCloud") { confirmingRebuild = true }
                .buttonStyle(.borderedProminent)
        }
        .confirmationDialog(
            "Rebuild your class from iCloud?",
            isPresented: $confirmingRebuild,
            titleVisibility: .visible
        ) {
            Button("Rebuild", role: .destructive) {
                Task { await bootstrapper.rebuildFromICloud() }
            }
        } message: {
            Text("The class and every mark already sent come back from iCloud. "
                + "Marks this iPhone hadn't sent yet are lost.")
        }
    }
}
