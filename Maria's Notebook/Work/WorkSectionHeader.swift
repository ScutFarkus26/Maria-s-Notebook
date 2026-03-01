import SwiftUI

struct WorkSectionHeader: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }
}
