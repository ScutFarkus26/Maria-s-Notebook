import SwiftUI

/// Asks the assistant what the guide should see beside her marks.
///
/// This has to be typed. CloudKit tells the guide the names of people who
/// joined his classroom, but it withholds your own name from you — so her
/// device cannot look up who she is, and with two assistants "assistant" stops
/// being an answer.
struct AssistantNameSheet: View {
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
                } header: {
                    Text("Who's marking?")
                } footer: {
                    Text("Your guide sees this beside the attendance you take, so he can tell your marks from anyone else's. First name is plenty.")
                }
            }
            .navigationTitle("Your Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ClassroomIdentity.displayName = trimmed
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
    }
}
