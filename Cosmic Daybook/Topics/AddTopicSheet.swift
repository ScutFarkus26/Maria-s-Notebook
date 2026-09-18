import SwiftUI

struct AddTopicSheet: View {
    var onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var issue: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Topic") {
                    TextField("Title", text: $title)
                    TextEditor(text: $issue)
                        .frame(minHeight: 120)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedTitle = title.trimmed()
                        onSave(trimmedTitle, issue)
                        dismiss()
                    }
                    .disabled(title.trimmed().isEmpty)
                }
            }
        }
    }
}
