// IntroductionCard.swift
// Maria's Notebook
//
// Manila/folder-styled card for curriculum introductions.

import SwiftUI

struct IntroductionCard: View {
    let introduction: CurriculumIntroduction
    let subjectColor: Color
    let onTap: () -> Void

    private var manilaBackground: Color {
        Color(red: 0.98, green: 0.96, blue: 0.90)
    }

    private var contentExcerpt: String {
        let content = introduction.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return "Tap to view introduction" }

        // Strip markdown headers and get plain text preview
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0) }
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }

        let preview = lines.prefix(3).joined(separator: " ")
        if preview.count > 140 {
            return String(preview.prefix(137)) + "..."
        }
        return preview.isEmpty ? "Tap to view introduction" : preview
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Header: Folder icon + Introduction label
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(subjectColor)

                    Text("Introduction")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()
                }

                // Title: Group name or Album
                Text(introduction.displayTitle)
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Content excerpt
                Text(contentExcerpt)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                // Bottom row: metadata badges
                HStack(spacing: 8) {
                    if let ageRange = introduction.ageRange, !ageRange.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                            Text(ageRange)
                                .font(AppTheme.ScaledFont.captionSmallSemibold)
                        }
                        .foregroundStyle(subjectColor.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(subjectColor.opacity(0.1))
                        )
                    }

                    if let prereqs = introduction.prerequisites, !prereqs.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 10))
                            Text("Prerequisites")
                                .font(AppTheme.ScaledFont.captionSmallSemibold)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.06))
                        )
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .lineSpacing(2)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 180) // Match paper card aspect ratio
            .background(introductionBackground)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    private var introductionBackground: some View {
        ZStack {
            // Manila paper base
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.18) : manilaBackground)

            // Warm manila tint in dark mode
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.06))
            }

            // Dashed border for folder feel
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    subjectColor.opacity(colorScheme == .dark ? 0.4 : 0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )

            // Folder tab accent at top-left
            folderTabAccent
        }
        // Paper-like shadow
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 1, x: 0, y: 1)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private var folderTabAccent: some View {
        GeometryReader { geo in
            Path { path in
                let tabWidth: CGFloat = 60
                let tabHeight: CGFloat = 8
                let cornerRadius: CGFloat = 12

                // Start at top-left after corner radius
                path.move(to: CGPoint(x: cornerRadius, y: 0))

                // Draw tab top edge
                path.addLine(to: CGPoint(x: tabWidth - 4, y: 0))

                // Tab notch down
                path.addQuadCurve(
                    to: CGPoint(x: tabWidth, y: tabHeight),
                    control: CGPoint(x: tabWidth, y: 0)
                )

                // Tab bottom edge
                path.addLine(to: CGPoint(x: cornerRadius, y: tabHeight))

                // Close back to start
                path.addLine(to: CGPoint(x: cornerRadius, y: 0))
            }
            .fill(subjectColor.opacity(0.15))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview("Group Introduction") {
    IntroductionCard(
        introduction: CurriculumIntroduction(
            subject: "Math",
            group: "Algebra",
            content: "## Introduction to Algebra\n\nAlgebra introduces students to abstract mathematical thinking through the use of variables and equations. This foundational work builds upon concrete number experiences.",
            prerequisites: "Decimal System, Four Operations",
            ageRange: "6-9"
        ),
        subjectColor: .indigo,
        onTap: {}
    )
    .frame(width: 280)
    .padding()
}

#Preview("Album Introduction") {
    IntroductionCard(
        introduction: CurriculumIntroduction(
            subject: "Language",
            group: nil,
            content: "The Language curriculum encompasses reading, writing, grammar, and oral expression. Children progress from concrete letter work through increasingly abstract linguistic concepts.",
            prerequisites: nil,
            ageRange: "3-12"
        ),
        subjectColor: .purple,
        onTap: {}
    )
    .frame(width: 280)
    .padding()
}

#Preview("Minimal Introduction") {
    IntroductionCard(
        introduction: CurriculumIntroduction(
            subject: "Science",
            group: "Botany",
            content: "# Botany\n\nPlant studies for the elementary classroom.",
            prerequisites: nil,
            ageRange: nil
        ),
        subjectColor: .teal,
        onTap: {}
    )
    .frame(width: 280)
    .padding()
}
