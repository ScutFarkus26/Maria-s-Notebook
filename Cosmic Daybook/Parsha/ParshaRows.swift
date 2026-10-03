// ParshaRows.swift
// Leaf rows for the parsha week view: upcoming parshiot, previous presentations,
// inline suggestions, and the topic bullet style.

import SwiftUI
import CoreData

struct UpcomingParshaRow: View {
    let date: Date
    let parshaKey: String?
    let festivalName: String?

    private var title: String {
        if let parshaKey { return HebrewParshaService.displayName(forKey: parshaKey) }
        if let festivalName { return festivalName }
        return "—"
    }

    private var isFestival: Bool { parshaKey == nil && festivalName != nil }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(isFestival ? Color.accentColor : .primary)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isFestival {
                Text("Festival")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, AppTheme.Spacing.small)
                    .padding(.vertical, AppTheme.Spacing.xxsmall)
                    .capsuleFill(Color.accentColor.opacity(0.12))
            }
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}

struct PreviousPresentationRow: View {
    @ObservedObject var assignment: CDLessonAssignment

    private var title: String {
        if let snapshot = assignment.lessonTitleSnapshot, !snapshot.isEmpty {
            return snapshot
        }
        if let lesson = assignment.lesson, !lesson.name.isEmpty {
            return lesson.name
        }
        return "Untitled Lesson"
    }

    private var detail: String {
        var parts: [String] = []
        if let date = assignment.presentedAt {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        let studentCount = assignment.studentIDs.count
        if studentCount > 0 {
            parts.append("\(studentCount) student\(studentCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
            Text(title)
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.primary)
            if !detail.isEmpty {
                Text(detail)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}

struct TopicBulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.small) {
            configuration.icon
                .imageScale(.small)
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
            configuration.title
                .foregroundStyle(.primary)
        }
    }
}

/// Hashable wrapper used to push the dedicated suggestions detail from inside a NavigationStack.
struct ParshaSuggestionsNav: Hashable {
    let parshaKey: String
}

struct InlineSuggestionRow: View {
    let suggestion: ParshaSuggestion
    let parshaKey: String

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    /// From the workspace's live lesson catalog: a lookup, not a fetch.
    private var lesson: CDLesson? {
        dependencies.lessonCatalog.lesson(id: suggestion.lessonID, in: viewContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
            if let lesson {
                NavigationLink(value: lesson) {
                    Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Text("Lesson no longer exists")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.secondary)
            }
            Text(suggestion.reasoning)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}
