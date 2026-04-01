import SwiftUI

struct WorkCheckInNoteEditor: View {
    // Decoupled from CDWorkCheckIn model so it works with Drafts too
    let date: Date
    let purpose: String
    
    @Binding var noteText: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add CDNote")
                .font(AppTheme.ScaledFont.titleSmall)
            
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
                    .font(AppTheme.ScaledFont.bodySemibold)
                
                let purposeText = purpose.trimmed()
                if !purposeText.isEmpty {
                    Text("|")
                        .foregroundStyle(.secondary)
                    Text(purposeText)
                        .font(AppTheme.ScaledFont.bodySemibold)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
    
    private var noteEditor: some View {
#if os(macOS)
        TextEditor(text: $noteText)
            .font(AppTheme.ScaledFont.body)
            .frame(minHeight: 120)
            .border(Color.primary.opacity(UIConstants.OpacityConstants.moderate), width: 1)
#else
        TextEditor(text: $noteText)
            .font(AppTheme.ScaledFont.body)
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
