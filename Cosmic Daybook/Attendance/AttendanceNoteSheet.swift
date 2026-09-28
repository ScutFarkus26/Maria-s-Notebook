import SwiftUI

/// Edits one child's attendance note for the day.
///
/// Used by the notebook's attendance screens and by the assistant's companion
/// app alike: the note sits on the shared attendance record, so both sides write
/// the same text. Saving empty text removes the note.
struct AttendanceNoteSheet: View {
    let studentName: String
    let initialText: String
    /// One line under the field saying who else reads the note.
    let sharedWith: String
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Note", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text(sharedWith)
                }
            }
            .navigationTitle(studentName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { text = initialText }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 200)
        #endif
    }
}
