import SwiftUI
import CoreData

struct StudentHeaderView: View {
    // The centered "tower" suits narrow modal/push contexts (iPhone); the leading
    // row reclaims ~250pt of vertical space in the wide split-view detail pane.
    enum Layout {
        case centered
        case leading
    }

    let fullName: String
    let levelDisplay: String
    let levelColor: Color
    let initials: String
    var layout: Layout = .centered
    /// When supplied, the level badge becomes a menu that reassigns the child's
    /// level in place. The badge is always on screen, so this stays reachable
    /// even when the surrounding chrome is not.
    var onChangeLevel: ((CDStudent.Level) -> Void)?

    // Keep the primitive initializer for callers that already provide pre-computed values.
    init(
        fullName: String,
        levelDisplay: String,
        levelColor: Color,
        initials: String,
        layout: Layout = .centered,
        onChangeLevel: ((CDStudent.Level) -> Void)? = nil
    ) {
        self.fullName = fullName
        self.levelDisplay = levelDisplay
        self.levelColor = levelColor
        self.initials = initials
        self.layout = layout
        self.onChangeLevel = onChangeLevel
    }

    // Convenience initializer that derives display values from a CDStudent model.
    init(student: CDStudent, layout: Layout = .centered, onChangeLevel: ((CDStudent.Level) -> Void)? = nil) {
        let fullName = student.fullName
        let levelDisplay = student.level.rawValue
        let levelColor = AppColors.color(forLevel: student.level)
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
        self.init(
            fullName: fullName,
            levelDisplay: levelDisplay,
            levelColor: levelColor,
            initials: initials,
            layout: layout,
            onChangeLevel: onChangeLevel
        )
    }

    var body: some View {
        switch layout {
        case .centered: centeredLayout
        case .leading: leadingLayout
        }
    }

    private var centeredLayout: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            avatar(size: 120, gradientEndRadius: 72, shadowRadius: 24, shadowY: 10, font: AppTheme.ScaledFont.titleXLarge)

            Text(fullName)
                .font(AppTheme.ScaledFont.titleXLarge)

            levelBadge(font: AppTheme.ScaledFont.bodySemibold, horizontalPadding: 14, verticalPadding: AppTheme.Spacing.small)
        }
        .frame(maxWidth: .infinity)
    }

    private var leadingLayout: some View {
        HStack(spacing: 16) {
            avatar(size: 64, gradientEndRadius: 38, shadowRadius: 10, shadowY: 4, font: AppTheme.ScaledFont.titleMedium)

            VStack(alignment: .leading, spacing: 6) {
                Text(fullName)
                    .font(AppTheme.ScaledFont.titleLarge)
                levelBadge(font: AppTheme.ScaledFont.captionSemibold, horizontalPadding: 10, verticalPadding: 4)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func avatar(size: CGFloat, gradientEndRadius: CGFloat, shadowRadius: CGFloat, shadowY: CGFloat, font: Font) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.purple, Color.pink]),
                        center: .center,
                        startRadius: 8,
                        endRadius: gradientEndRadius
                    )
                )
                .frame(width: size, height: size)
                .shadow(
                    color: Color.pink.opacity(UIConstants.OpacityConstants.quarter),
                    radius: shadowRadius, x: 0, y: shadowY
                )

            Text(initials)
                .font(font)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func levelBadge(font: Font, horizontalPadding: CGFloat, verticalPadding: CGFloat) -> some View {
        if let onChangeLevel {
            Menu {
                ForEach(CDStudent.Level.allCases, id: \.self) { level in
                    Button {
                        onChangeLevel(level)
                    } label: {
                        if level.rawValue == levelDisplay {
                            Label(level.rawValue, systemImage: "checkmark")
                        } else {
                            Text(level.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(levelDisplay)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(UIConstants.OpacityConstants.semi)
                }
                .font(font)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Capsule().fill(levelColor.opacity(UIConstants.OpacityConstants.medium)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change this student's level")
            .accessibilityLabel("Level: \(levelDisplay). Change level.")
        } else {
            levelText(font: font, horizontalPadding: horizontalPadding, verticalPadding: verticalPadding)
        }
    }

    private func levelText(font: Font, horizontalPadding: CGFloat, verticalPadding: CGFloat) -> some View {
        Text(levelDisplay)
            .font(font)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Capsule().fill(levelColor.opacity(UIConstants.OpacityConstants.medium)))
    }
}
