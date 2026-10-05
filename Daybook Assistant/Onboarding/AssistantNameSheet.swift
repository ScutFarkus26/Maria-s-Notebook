import SwiftUI

/// Asks the assistant what the guide should see beside her marks.
///
/// This has to be typed. CloudKit tells the guide the names of people who
/// joined his classroom, but it withholds your own name from you — so her
/// device cannot look up who she is, and with two assistants "assistant" stops
/// being an answer.
///
/// The first run after joining asks in setup (`AssistantSetupNamePage`).
/// This sheet asks when a name is missing after that, and then it can't be
/// swiped away: a term's marks under no name at all is what asking up front
/// is for.
struct AssistantNameSheet: View {
    /// Asked for a missing name: no Cancel, and no dismissing without one.
    var isRequired = false

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ClassroomIdentity.displayName ?? ""
    /// Where `ClassroomIdentity.displayName` is kept, watched so a name
    /// restored from iCloud while the sheet is open fills it in.
    @AppStorage(UserDefaultsKeys.classroomIdentityDisplayName) private var storedName: String?

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
        .onChange(of: storedName) { _, stored in
            if let restored = Self.restoredName(typed: name, stored: stored) { name = restored }
        }
    }

    /// The name to fill in when one arrives from iCloud while she's being
    /// asked: only into an empty field, never over what she's typing.
    static func restoredName(typed: String, stored: String?) -> String? {
        guard typed.trimmed().isEmpty, let stored = stored?.trimmed(), !stored.isEmpty else { return nil }
        return stored
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        AssistantNameStore.save(trimmed)
        dismiss()
    }
}
