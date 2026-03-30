// GreatLessonCard.swift
// Card component showing a single Great Lesson with lesson count and subject breakdown.

import SwiftUI

struct GreatLessonCard: View {
    let data: GreatLessonCardData

    private var greatLesson: GreatLesson { data.greatLesson }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: icon + title
            HStack(spacing: 10) {
                Image(systemName: greatLesson.icon)
                    .font(.title2)
                    .foregroundStyle(greatLesson.color)
                    .frame(width: 40, height: 40)
                    .background(
                        greatLesson.color.opacity(UIConstants.OpacityConstants.medium),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(greatLesson.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(greatLesson.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Lesson count
                Text("\(data.lessonCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(data.lessonCount > 0 ? greatLesson.color : Color.gray.opacity(0.5))
            }

            // Subject dots
            if !data.subjects.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(data.subjects, id: \.self) { subject in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppColors.color(forSubject: subject))
                                .frame(width: 6, height: 6)
                            Text(subject)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Student coverage bar
            if data.totalStudentCount > 0 {
                HStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))

                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(greatLesson.color.gradient)
                                .frame(width: max(0, geo.size.width * data.coveragePercentage))
                        }
                    }
                    .frame(height: 6)

                    Text("\(data.studentsPresentedCount)/\(data.totalStudentCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .fill(CardStyle.cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(CardStyle.strokeOpacity))
        )
        .shadow(color: CardStyle.shadowColor, radius: CardStyle.shadowRadius, y: 1)
    }
}
