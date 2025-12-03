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
                    .font(.system(size: AppTheme.FontSize.caption))
            }

            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .font(.system(size: AppTheme.FontSize.caption))

            Button("Save") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: AppTheme.FontSize.caption))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, 8)
    }
}
