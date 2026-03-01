import SwiftUI

struct WorkDetailBottomBar: View {
    let onDelete: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        HStack {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(AppTheme.ScaledFont.caption)
            }

            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .font(AppTheme.ScaledFont.caption)

            Button("Save") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .font(AppTheme.ScaledFont.caption)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, 8)
    }
}
