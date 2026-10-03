import SwiftUI

// MARK: - CDNote Tags Display

private struct NoteTagsRow: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(3), id: \.self) { tag in
                    TagBadge(tag: tag, compact: true)
                }
            }
        }
    }
}

// MARK: - CDNote Row View

struct NoteRowView: View {
    let note: CDNote
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.body)
                .font(AppTheme.ScaledFont.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                NoteTagsRow(tags: note.tagsArray)

                Text(note.createdAt ?? Date(), style: .date)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    ActionIconButton(icon: "pencil.circle.fill", color: .blue, action: onEdit)
                    ActionIconButton(icon: "trash.circle.fill", color: .red, action: onDelete)
                }
            }
        }
        .padding(14)
        .surface(
            UIConstants.CornerRadius.large,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.whisper),
            stroke: Color.primary.opacity(UIConstants.OpacityConstants.veryFaint),
            lineWidth: 1
        )
    }
}

// MARK: - Action Icon Button

private struct ActionIconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}
