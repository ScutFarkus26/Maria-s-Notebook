import SwiftUI

struct QuickBannerView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(UIConstants.OpacityConstants.barelyTransparent))
            )
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
            .padding(.top, 8)
    }
}
