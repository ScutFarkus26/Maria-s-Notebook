import SwiftUI

struct WorkCheckInNoteEditor: View {
    // Decoupled from WorkCheckIn model so it works with Drafts too
    let date: Date
    let purpose: String
    
    @Binding var noteText: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Note")
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
            
            checkInInfo
            
            Divider()
            
            noteEditor
            
            actionButtons
        }
        .padding(20)
#if os(macOS)
        .frame(minWidth: 440, minHeight: 320)
        .presentationSizingFitted()
#else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }
    
    private var checkInInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                
                let purposeText = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
                if !purposeText.isEmpty {
                    Text("|")
                        .foregroundStyle(.secondary)
                    Text(purposeText)
                        .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                }
            }
            .foregroundStyle(.secondary)
        }
    }
    
    private var noteEditor: some View {
#if os(macOS)
        TextEditor(text: $noteText)
            .font(.system(size: AppTheme.FontSize.body))
            .frame(minHeight: 120)
            .border(Color.primary.opacity(0.2), width: 1)
#else
        TextEditor(text: $noteText)
            .font(.system(size: AppTheme.FontSize.body))
            .frame(minHeight: 120)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
#endif
    }
    
    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                onCancel()
            }
            Button("Save") {
                onSave()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }
}
