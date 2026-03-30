// GreatLessonDetailView.swift
// Detail view showing all lessons tagged to a specific Great Lesson, grouped by subject.

import SwiftUI
import SwiftData

struct GreatLessonDetailView: View {
    let greatLesson: GreatLesson
    let lessons: [Lesson]

    @Environment(\.modelContext) private var modelContext

    private var lessonsBySubject: [(subject: String, lessons: [Lesson])] {
        let grouped = Dictionary(grouping: lessons, by: \.subject)
        return grouped
            .sorted { $0.key < $1.key }
            .map { (subject: $0.key, lessons: $0.value.sorted { $0.sortIndex < $1.sortIndex }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header card
                headerCard
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Lessons grouped by subject
                if lessons.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    ForEach(lessonsBySubject, id: \.subject) { group in
                        subjectSection(group.subject, lessons: group.lessons)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(greatLesson.shortName)
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: greatLesson.icon)
                .font(.title)
                .foregroundStyle(greatLesson.color)
                .frame(width: 48, height: 48)
                .background(greatLesson.color.opacity(UIConstants.OpacityConstants.medium), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(greatLesson.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(greatLesson.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(lessons.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(greatLesson.color)
                Text("lessons")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .cardStyle()
    }

    // MARK: - Subject Section

    private func subjectSection(_ subject: String, lessons: [Lesson]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.color(forSubject: subject))
                    .frame(width: 8, height: 8)
                Text(subject)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("(\(lessons.count))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            LazyVStack(spacing: 6) {
                ForEach(lessons) { lesson in
                    lessonRow(lesson)
                }
            }
        }
    }

    private func lessonRow(_ lesson: Lesson) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !lesson.group.isEmpty {
                    Text(lesson.group)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Presentation count
            let count = lesson.lessonAssignments?.count ?? 0
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CardStyle.cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(CardStyle.strokeOpacity))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Lessons Tagged", systemImage: greatLesson.icon)
        } description: {
            Text("Tag lessons with this Great Lesson connection to see them here.")
        }
    }
}
