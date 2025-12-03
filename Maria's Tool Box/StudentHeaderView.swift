import SwiftUI

struct StudentHeaderView: View {
    let fullName: String
    let levelDisplay: String
    let levelColor: Color
    let initials: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [Color.purple, Color.pink]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 72
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.pink.opacity(0.25), radius: 24, x: 0, y: 10)

                Text(initials)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(fullName)
                .font(.system(size: AppTheme.FontSize.titleXLarge, weight: .black, design: .rounded))

            Text(levelDisplay)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(levelColor.opacity(0.12)))
        }
        .frame(maxWidth: .infinity)
    }
}
