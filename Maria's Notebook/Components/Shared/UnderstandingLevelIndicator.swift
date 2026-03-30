import SwiftUI

/// A reusable component for displaying understanding levels (1-5 scale)
/// Used across presentation and student tracking views
struct UnderstandingLevelIndicator: View {
    let level: Int?
    let size: CGFloat
    let showLabel: Bool
    
    init(level: Int?, size: CGFloat = 28, showLabel: Bool = false) {
        self.level = level
        self.size = size
        self.showLabel = showLabel
    }
    
    var body: some View {
        if let level {
            if showLabel {
                HStack(spacing: 6) {
                    circle
                    Text(UnderstandingLevel.label(for: level))
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                }
            } else {
                circle
            }
        } else {
            Circle()
                .fill(Color.secondary.opacity(UIConstants.OpacityConstants.moderate))
                .frame(width: size, height: size)
                .overlay(
                    Text("?")
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(.secondary)
                )
        }
    }
    
    private var circle: some View {
        Circle()
            .fill(UnderstandingLevel.color(for: level ?? 3))
            .frame(width: size, height: size)
            .overlay(
                Text("\(level ?? 0)")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

/// Understanding level helpers consolidated from multiple files
enum UnderstandingLevel {
    static func color(for level: Int) -> Color {
        switch level {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        case 5: return .blue
        default: return .gray
        }
    }
    
    static func label(for level: Int) -> String {
        switch level {
        case 1: return "Struggling"
        case 2: return "Needs Support"
        case 3: return "Developing"
        case 4: return "Proficient"
        case 5: return "Mastery"
        default: return "Unknown"
        }
    }
}
