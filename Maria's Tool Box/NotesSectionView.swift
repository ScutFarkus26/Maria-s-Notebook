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
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        Divider()
                            .background(Color.secondary.opacity(0.1))
                            .padding(.vertical, 16)
                    }
                }
                .allowsHitTesting(false)

                TextEditor(text: $notes)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 180)
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(notesBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
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

