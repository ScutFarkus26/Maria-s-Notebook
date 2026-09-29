import SwiftUI

/// Asks the assistant what the guide should see beside her marks.
///
/// This has to be typed. CloudKit tells the guide the names of people who
/// joined his classroom, but it withholds your own name from you — so her
/// device cannot look up who she is, and with two assistants "assistant" stops
/// being an answer.
///
/// On the first run after joining it can't be swiped away: a term's marks
/// under no name at all is what asking up front is for.
struct AssistantNameSheet: View {
    /// First run: no Cancel, and no dismissing without a name.
    var isRequired = false

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ClassroomIdentity.displayName ?? ""

    private var trimmed: String { name.trimmed() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                } header: {
                    Text("Who's marking?")
                } footer: {
                    Text("Shown beside the attendance you take, so your guide can tell your marks "
                        + "from anyone else's. First name is plenty.")
                }
            }
            .navigationTitle("Your Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isRequired {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(isRequired)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        AssistantNameStore.save(trimmed)
        dismiss()
    }
}
