import SwiftUI

struct NotesSectionView: View {
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                Text("Notes")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $notes)
                .font(AppTheme.ScaledFont.body)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 180)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(notesBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.accent), lineWidth: 1)
                )
        }
    }
    
    private var notesBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        #else
        return Color(uiColor: .secondarySystemBackground).opacity(0.5)
        #endif
    }
}
