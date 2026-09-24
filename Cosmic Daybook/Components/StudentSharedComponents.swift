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
        .surface(
            cornerRadius,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.hint),
            stroke: Color.primary.opacity(UIConstants.OpacityConstants.subtle),
            style: .continuous
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
                    .surface(
                        UIConstants.CornerRadius.control,
                        fill: Color.primary.opacity(UIConstants.OpacityConstants.trace),
                        stroke: Color.primary.opacity(UIConstants.OpacityConstants.subtle),
                        style: .continuous
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
    let level: CDStudent.Level
    let backgroundColor: Color
    let useWhiteBackground: Bool

    init(level: CDStudent.Level, backgroundColor: Color? = nil, useWhiteBackground: Bool = false) {
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
        .capsuleFill(bgColor)
        .accessibilityLabel("Level: \(level.rawValue)")
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
