import SwiftUI

/// A small rounded label beside a child's name: "Absent", "Birthday Tue".
struct RosterTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}
