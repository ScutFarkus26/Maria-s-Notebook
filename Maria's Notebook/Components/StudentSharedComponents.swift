// StudentSharedComponents.swift
// Shared UI components extracted from student-related views to reduce duplication

import SwiftUI

// MARK: - Card Container

/// A reusable card wrapper with consistent styling
struct CardContainer<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let padding: CGFloat

    init(
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(padding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
        )
    }
}

// MARK: - Text Area with Placeholder

/// A styled TextEditor with placeholder support
struct PlaceholderTextArea: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    init(
        title: String,
        text: Binding<String>,
        placeholder: String,
        minHeight: CGFloat = 80
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: minHeight)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                    )
                if text.trimmed().isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
        }
    }
}

// MARK: - Label-Value Row

/// A simple row displaying a label and value
struct LabelValueRow: View {
    let label: String
    let value: String
    let spacing: CGFloat

    init(label: String, value: String, spacing: CGFloat = 8) {
        self.label = label
        self.value = value
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            Text("\(label):")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Detail Line (for expanded sections)

/// A row for displaying detailed information with aligned labels
struct DetailLine: View {
    let title: String
    let text: String
    let spacing: CGFloat

    init(title: String, text: String, spacing: CGFloat = 6) {
        self.title = title
        self.text = text
        self.spacing = spacing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text("\(title):")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Level Badge

/// A reusable level badge component
struct LevelBadge: View {
    let level: Student.Level
    let backgroundColor: Color
    let useWhiteBackground: Bool

    init(level: Student.Level, backgroundColor: Color? = nil, useWhiteBackground: Bool = false) {
        self.level = level
        self.backgroundColor = backgroundColor ?? AppColors.color(forLevel: level)
        self.useWhiteBackground = useWhiteBackground
    }

    private var bgColor: Color {
        useWhiteBackground ? Color.white.opacity(0.18) : backgroundColor.opacity(UIConstants.OpacityConstants.medium)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(backgroundColor)
                .frame(width: 6, height: 6)
            Text(level.rawValue)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(backgroundColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(bgColor))
        .accessibilityLabel("Level: \(level.rawValue)")
    }
}

// MARK: - Bobbing Animation Modifier

/// A reusable view modifier for bobbing animation that respects scene phase
struct BobbingAnimationModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var bob: Bool
    let duration: Double
    let offset: CGFloat

    init(bob: Binding<Bool>, duration: Double = 1.6, offset: CGFloat = 2) {
        self._bob = bob
        self.duration = duration
        self.offset = offset
    }

    private var isAnimating: Bool {
        #if os(macOS)
        false
        #else
        scenePhase == .active
        #endif
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content
            .offset(y: bob ? -offset : offset)
            .adaptiveAnimation(
                isAnimating ? .easeInOut(duration: duration).repeatCount(60, autoreverses: true) : nil,
                value: bob
            )
            .onAppear { bob = true }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    bob = true
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        bob = false
                    }
                }
            }
        #endif
    }
}

extension View {
    /// Applies a bobbing animation that respects scene phase for energy efficiency
    func bobbingAnimation(bob: Binding<Bool>, duration: Double = 1.6, offset: CGFloat = 2) -> some View {
        modifier(BobbingAnimationModifier(bob: bob, duration: duration, offset: offset))
    }

    /// Avoid offscreen rasterization on macOS where the student card grids can
    /// create sustained RenderBox pressure during navigation and layout.
    @ViewBuilder
    func studentCardRasterization() -> some View {
        #if os(macOS)
        self
        #else
        self.drawingGroup()
        #endif
    }
}

// MARK: - Section Header

/// A reusable section header with consistent styling
struct SectionHeaderView: View {
    let title: String
    let icon: String?
    let iconColor: Color?

    init(title: String, icon: String? = nil, iconColor: Color? = nil) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
    }

    var body: some View {
        HStack(spacing: icon != nil ? 6 : 0) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(iconColor ?? .secondary)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(iconColor?.opacity(UIConstants.OpacityConstants.subtle) ?? .clear)
    }
}

// MARK: - Filter Chip

/// A reusable filter chip component (for category filters, etc.)
struct StudentFilterChip: View {
    let label: String
    let icon: String?
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    init(
        label: String,
        icon: String? = nil,
        color: Color = .secondary,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.color = color
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? color.opacity(UIConstants.OpacityConstants.moderate) : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? color : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bullet Point Row

/// A simple bullet point row for lists
struct BulletPointRow: View {
    let text: String
    let icon: String
    let iconSize: CGFloat
    let spacing: CGFloat

    init(
        text: String,
        icon: String = "circle.fill",
        iconSize: CGFloat = 6,
        spacing: CGFloat = 6
    ) {
        self.text = text
        self.icon = icon
        self.iconSize = iconSize
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
