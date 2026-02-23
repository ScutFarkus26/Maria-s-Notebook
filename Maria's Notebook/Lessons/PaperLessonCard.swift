// PaperLessonCard.swift
// Maria's Notebook
//
// Paper-styled lesson card with subtle shadows and content preview.

import SwiftUI

struct PaperLessonCard: View {
    let lesson: Lesson
    let statusCount: Int?
    let lastPresentedDate: Date?

    private var isPersonal: Bool {
        lesson.source == .personal
    }

    private var subjectColor: Color {
        AppColors.color(forSubject: lesson.subject)
    }

    /// Paper-like background color - slightly warm/cream tinted
    private var paperColor: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    /// Cream tint for paper effect
    private var paperTint: Color {
        Color(red: 1.0, green: 0.99, blue: 0.96)
    }

    private var writeUpExcerpt: String? {
        let trimmed = lesson.writeUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Get first two lines or first 120 characters
        let lines = trimmed.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: true)
        let firstTwo = lines.prefix(2).joined(separator: " ")
        if firstTwo.count > 120 {
            return String(firstTwo.prefix(117)) + "..."
        }
        return firstTwo
    }

    private var hasAttachment: Bool {
        lesson.pagesFileBookmark != nil || lesson.pagesFileRelativePath != nil
    }
    
    private var attachmentCount: Int {
        var count = 0
        // Count legacy Pages file
        if hasAttachment {
            count += 1
        }
        // Count new attachments
        if let attachments = lesson.attachments {
            count += attachments.count
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: Name + Personal badge
            HStack(alignment: .top, spacing: 8) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                if isPersonal {
                    Text(lesson.personalKind?.badgeLabel ?? "Personal")
                        .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                        .foregroundStyle(.orange)
                }
            }

            // Content preview: Subheading or writeUp excerpt
            if !lesson.subheading.isEmpty {
                Text(lesson.subheading)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let excerpt = writeUpExcerpt {
                Text(excerpt)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            // Bottom row: metadata badges
            HStack(spacing: 8) {
                // Subject + Group
                if !lesson.group.isEmpty || !lesson.subject.isEmpty {
                    Text(groupSubjectLine)
                        .font(.system(size: AppTheme.FontSize.captionSmall, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Attachment indicator with count
                if attachmentCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                        if attachmentCount > 1 {
                            Text("\(attachmentCount)")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                    }
                    .foregroundStyle(.secondary.opacity(0.7))
                }

                // Status count badge
                if let count = statusCount, count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9))
                        Text("\(count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .overlay(Capsule().stroke(Color.orange.opacity(0.4), lineWidth: 0.5))
                    .foregroundStyle(.orange)
                }
            }
        }
        .lineSpacing(2)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 180) // Taller for paper-like 3:4 aspect ratio
        .background(paperBackground)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var groupSubjectLine: String {
        switch (lesson.subject.isEmpty, lesson.group.isEmpty) {
        case (false, false): return "\(lesson.subject) \u{2022} \(lesson.group)"
        case (false, true): return lesson.subject
        case (true, false): return lesson.group
        default: return ""
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    private var paperBackground: some View {
        ZStack {
            // Base paper with cream/off-white tint
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(paperColor)

            // Paper tint overlay (more visible in light mode)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(paperTint.opacity(colorScheme == .dark ? 0.03 : 0.5))

            // Personal lesson warm tint overlay
            if isPersonal {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.08 : 0.06))
            }

            // Subtle inner shadow/gradient for depth (paper edge effect)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02),
                            Color.clear,
                            Color.clear,
                            Color.white.opacity(colorScheme == .dark ? 0.03 : 0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Border - subtle but visible
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.black.opacity(0.08),
                    lineWidth: 1
                )

            // Left accent bar with subject color
            HStack {
                Rectangle()
                    .fill(subjectColor)
                    .frame(width: 5)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 12,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                    )
                Spacer()
            }

            // Corner fold accent (top-right)
            cornerFold
        }
        // More pronounced shadow for paper-on-desk effect
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 1, x: 0, y: 1)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
    }

    /// Corner fold accent for paper effect
    @ViewBuilder
    private var cornerFold: some View {
        GeometryReader { geo in
            let foldSize: CGFloat = 16
            Path { path in
                // Triangle in top-right corner
                path.move(to: CGPoint(x: geo.size.width - foldSize, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: foldSize))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        colorScheme == .dark
                            ? Color.white.opacity(0.06)
                            : Color.black.opacity(0.04),
                        colorScheme == .dark
                            ? Color.white.opacity(0.02)
                            : Color.black.opacity(0.01)
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview("Album Lesson") {
    PaperLessonCard(
        lesson: Lesson(
            name: "Introduction to Decimal System",
            subject: "Math",
            group: "Number Work",
            subheading: "Understanding base-10 and place value concepts",
            writeUp: "This foundational presentation introduces students to the decimal system."
        ),
        statusCount: 5,
        lastPresentedDate: Date().addingTimeInterval(-86400 * 7)
    )
    .frame(width: 280)
    .padding()
}

#Preview("Personal Lesson") {
    let lesson = Lesson(
        name: "Bird Observation Activity",
        subject: "Science",
        group: "Zoology",
        subheading: "",
        writeUp: "A custom observation activity for tracking local bird species in the school garden."
    )
    lesson.source = .personal
    lesson.personalKind = .observation

    return PaperLessonCard(
        lesson: lesson,
        statusCount: nil,
        lastPresentedDate: nil
    )
    .frame(width: 280)
    .padding()
}

#Preview("Minimal Lesson") {
    PaperLessonCard(
        lesson: Lesson(
            name: "Parts of Speech",
            subject: "Language",
            group: "",
            subheading: "",
            writeUp: ""
        ),
        statusCount: nil,
        lastPresentedDate: nil
    )
    .frame(width: 280)
    .padding()
}
