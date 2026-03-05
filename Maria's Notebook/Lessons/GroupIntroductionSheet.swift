// Maria's Notebook/Lessons/GroupIntroductionSheet.swift
//
// Sheet view for displaying album and group introductions.
// Renders markdown content with proper styling.

import SwiftUI

struct GroupIntroductionSheet: View {
    let introduction: CurriculumIntroduction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Metadata badges
                    if introduction.prerequisites != nil || introduction.ageRange != nil {
                        metadataBadges
                    }

                    // Main content
                    markdownContent

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(sheetBackground)
            .navigationTitle(introduction.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, maxWidth: 700)
        .frame(minHeight: 400, idealHeight: 600, maxHeight: 800)
        #endif
    }

    // MARK: - Subviews

    @ViewBuilder
    private var metadataBadges: some View {
        HStack(spacing: 12) {
            if let prerequisites = introduction.prerequisites, !prerequisites.isEmpty {
                metadataBadge(icon: "arrow.right.circle", label: "Prerequisites", value: prerequisites)
            }

            if let ageRange = introduction.ageRange, !ageRange.isEmpty {
                metadataBadge(icon: "person.2", label: "Ages", value: ageRange)
            }

            Spacer()
        }
    }

    private func metadataBadge(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Text(value)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    @ViewBuilder
    private var markdownContent: some View {
        if let attributedString = parseMarkdown(introduction.content) {
            Text(attributedString)
                .font(AppTheme.ScaledFont.body)
                .lineSpacing(6)
                .textSelection(.enabled)
        } else {
            // Fallback for plain text
            Text(introduction.content)
                .font(AppTheme.ScaledFont.body)
                .lineSpacing(6)
                .textSelection(.enabled)
        }
    }

    private var sheetBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    // MARK: - Markdown Parsing

    private func parseMarkdown(_ markdown: String) -> AttributedString? {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            return try AttributedString(markdown: markdown, options: options)
        } catch {
            // If inline parsing fails, try full markdown
            do {
                return try AttributedString(markdown: markdown)
            } catch {
                return nil
            }
        }
    }
}

// MARK: - Preview

#Preview("Group Introduction") {
    GroupIntroductionSheet(
        introduction: CurriculumIntroduction(
            subject: "Math",
            group: "Algebra",
            content: """
            # Algebra

            ## Introduction to Algebra

            We approach algebra in the elementary classroom as a puzzle \
            to solve. Be clear with children about this framing—they \
            may be hearing at home that algebra is hard or intimidating.

            ## What Is Algebra?

            Mathematics has three branches: geometry, arithmetic, and algebra.

            **Arithmetic** concerns itself with the properties of and relationships between real numbers.

            **Algebra**, in contrast, expresses itself through variables and symbols.
            """,
            prerequisites: "Sensorial work",
            ageRange: "6-9"
        )
    )
}

#Preview("Album Introduction") {
    GroupIntroductionSheet(
        introduction: CurriculumIntroduction(
            subject: "Math",
            group: nil,
            content: """
            # Math Album

            The mathematics curriculum guides children from concrete \
            manipulation to abstract understanding through carefully \
            sequenced materials.
            """
        )
    )
}
