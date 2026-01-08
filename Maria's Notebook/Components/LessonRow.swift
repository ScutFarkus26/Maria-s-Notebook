// LessonRow.swift
// Shared component for displaying lesson rows in list views

import SwiftUI

struct LessonRow: View {
    let lesson: Lesson
    
    /// The style of secondary text to display
    enum SecondaryTextStyle {
        case subjectAndGroup  // Shows "subject · group"
        case subheading       // Shows subheading if present
    }
    
    let secondaryTextStyle: SecondaryTextStyle
    let showTagIcon: Bool
    
    init(
        lesson: Lesson,
        secondaryTextStyle: SecondaryTextStyle = .subheading,
        showTagIcon: Bool = false
    ) {
        self.lesson = lesson
        self.secondaryTextStyle = secondaryTextStyle
        self.showTagIcon = showTagIcon
    }
    
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(secondaryTextStyle == .subjectAndGroup ? 1 : nil)
                
                Group {
                    switch secondaryTextStyle {
                    case .subjectAndGroup:
                        Text("\(lesson.subject) · \(lesson.group)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    case .subheading:
                        if !lesson.subheading.isEmpty {
                            Text(lesson.subheading)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            if showTagIcon {
                // Structural affordance only (no student tracking)
                Image(systemName: "tag.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.45))
            }
        }
        .padding(.vertical, secondaryTextStyle == .subjectAndGroup ? 6 : 2)
        .contentShape(Rectangle())
    }
}
