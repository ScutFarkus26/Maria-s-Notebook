// LessonsFilterChipBar.swift
// Maria's Notebook
//
// Horizontal scrolling chip bar for quick lesson filtering.

import SwiftUI

struct LessonsFilterChipBar: View {
    @Binding var sourceFilter: LessonSource?
    @Binding var personalKindFilter: PersonalLessonKind?
    @Binding var formatFilter: LessonFormat?
    @Binding var hasAttachmentFilter: Bool
    @Binding var needsAttentionFilter: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Source filter chips
                sourceFilterChips

                // Divider when personal selected and showing kind filters
                if sourceFilter == .personal {
                    verticalDivider
                    personalKindChips
                }

                // Additional filter chips
                verticalDivider
                additionalFilterChips
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Source Filter Chips

    @ViewBuilder
    private var sourceFilterChips: some View {
        FilterChip(
            label: "All",
            isActive: sourceFilter == nil,
            onTap: { sourceFilter = nil; personalKindFilter = nil }
        )

        FilterChip(
            label: "Album",
            icon: "book.closed.fill",
            isActive: sourceFilter == .album,
            onTap: {
                sourceFilter = sourceFilter == .album ? nil : .album
                personalKindFilter = nil
            }
        )

        FilterChip(
            label: "Personal",
            icon: "person.fill",
            isActive: sourceFilter == .personal,
            onTap: {
                sourceFilter = sourceFilter == .personal ? nil : .personal
                if sourceFilter != .personal {
                    personalKindFilter = nil
                }
            }
        )
    }

    // MARK: - Personal Kind Chips

    @ViewBuilder
    private var personalKindChips: some View {
        ForEach(PersonalLessonKind.allCases) { kind in
            FilterChip(
                label: kind.shortLabel,
                isActive: personalKindFilter == kind,
                onTap: {
                    personalKindFilter = personalKindFilter == kind ? nil : kind
                }
            )
        }
    }

    // MARK: - Additional Filters

    @ViewBuilder
    private var additionalFilterChips: some View {
        FilterChip(
            label: "Stories",
            icon: "book.pages",
            isActive: formatFilter == .story,
            activeColor: .purple,
            onTap: { formatFilter = formatFilter == .story ? nil : .story }
        )

        FilterChip(
            label: "Has File",
            icon: "doc.fill",
            isActive: hasAttachmentFilter,
            onTap: { hasAttachmentFilter.toggle() }
        )

        FilterChip(
            label: "Needs Attention",
            icon: "exclamationmark.circle.fill",
            isActive: needsAttentionFilter,
            activeColor: .orange,
            onTap: { needsAttentionFilter.toggle() }
        )
    }

    // MARK: - Divider

    @ViewBuilder
    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}

// MARK: - Filter Chip Component

struct FilterChip: View {
    let label: String
    var icon: String?
    let isActive: Bool
    var activeColor: Color = .accentColor
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(isActive ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isActive ? activeColor.opacity(0.15) : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(isActive ? activeColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isActive ? activeColor : .secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

// MARK: - PersonalLessonKind Short Labels

extension PersonalLessonKind {
    /// Short label for chip display (more compact than full label).
    var shortLabel: String {
        switch self {
        case .personal: return "Custom"
        case .observation: return "Observation"
        case .adaptation: return "Adaptation"
        case .studentRequested: return "Student Ask"
        case .external: return "External"
        }
    }
}

// MARK: - Preview

#Preview("Filter Bar - Default") {
    struct PreviewWrapper: View {
        @State private var source: LessonSource?
        @State private var kind: PersonalLessonKind?
        @State private var format: LessonFormat?
        @State private var hasFile = false
        @State private var needsAttention = false

        var body: some View {
            VStack {
                LessonsFilterChipBar(
                    sourceFilter: $source,
                    personalKindFilter: $kind,
                    formatFilter: $format,
                    hasAttachmentFilter: $hasFile,
                    needsAttentionFilter: $needsAttention
                )

                Text("Source: \(source?.rawValue ?? "nil")")
                Text("Kind: \(kind?.rawValue ?? "nil")")
                Text("Format: \(format?.rawValue ?? "nil")")
                Text("Has File: \(hasFile.description)")
                Text("Needs Attention: \(needsAttention.description)")
            }
        }
    }
    return PreviewWrapper()
}

#Preview("Filter Bar - Personal Selected") {
    struct PreviewWrapper: View {
        @State private var source: LessonSource? = .personal
        @State private var kind: PersonalLessonKind? = .observation
        @State private var format: LessonFormat?
        @State private var hasFile = false
        @State private var needsAttention = true

        var body: some View {
            LessonsFilterChipBar(
                sourceFilter: $source,
                personalKindFilter: $kind,
                formatFilter: $format,
                hasAttachmentFilter: $hasFile,
                needsAttentionFilter: $needsAttention
            )
        }
    }
    return PreviewWrapper()
}
