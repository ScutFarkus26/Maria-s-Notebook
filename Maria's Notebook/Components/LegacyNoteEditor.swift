import SwiftUI

/// Simple editor for legacy note types (ScopedNote, WorkNote, MeetingNote)
/// that don't support the full UnifiedNoteEditor features
struct LegacyNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    
    let title: String
    @State private var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    init(title: String, text: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        _text = State(initialValue: text)
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            
            TextEditor(text: $text)
                .font(.system(size: 17, design: .rounded))
                .frame(minHeight: 200)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onSave(trimmed)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 380)
        .presentationSizingFitted()
        #else
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextEditor(text: $text)
                    .font(.system(size: 17, design: .rounded))
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onSave(trimmed)
                        }
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}


