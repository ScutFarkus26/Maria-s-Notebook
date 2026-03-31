import SwiftUI
import CoreData

struct StudentHeaderView: View {
    let fullName: String
    let levelDisplay: String
    let levelColor: Color
    let initials: String

    // Keep the primitive initializer for callers that already provide pre-computed values.
    init(fullName: String, levelDisplay: String, levelColor: Color, initials: String) {
        self.fullName = fullName
        self.levelDisplay = levelDisplay
        self.levelColor = levelColor
        self.initials = initials
    }

    // Convenience initializer that derives display values from a CDStudent model.
    init(student: CDStudent) {
        let fullName = student.fullName
        let levelDisplay = student.level.rawValue
        let levelColor: Color = {
            switch student.level {
            case .upper: return .pink
            case .lower: return .blue
            }
        }()
        let initials: String = {
            let parts = student.fullName.split(separator: " ")
            if parts.count >= 2 {
                let first = parts.first?.first.map(String.init) ?? ""
                let last = parts.last?.first.map(String.init) ?? ""
                return (first + last).uppercased()
            } else if let first = student.fullName.first {
                return String(first).uppercased()
            } else {
                return "?"
            }
        }()
        self.init(fullName: fullName, levelDisplay: levelDisplay, levelColor: levelColor, initials: initials)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
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
                    .shadow(color: Color.pink.opacity(UIConstants.OpacityConstants.quarter), radius: 24, x: 0, y: 10)

                Text(initials)
                    .font(AppTheme.ScaledFont.titleXLarge)
                    .foregroundStyle(.white)
            }

            Text(fullName)
                .font(AppTheme.ScaledFont.titleXLarge)

            Text(levelDisplay)
                .font(AppTheme.ScaledFont.bodySemibold)
                .padding(.horizontal, 14)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(Capsule().fill(levelColor.opacity(UIConstants.OpacityConstants.medium)))
        }
        .frame(maxWidth: .infinity)
    }
}
