import SwiftUI

struct QuickBannerView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.95))
            )
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            .padding(.top, 8)
    }
}
