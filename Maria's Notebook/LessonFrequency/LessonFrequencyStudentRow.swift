// LessonFrequencyStudentRow.swift
// Card showing one student's weekly lesson count with subject breakdown.
// Design follows ProgressDashboardStudentCard: initials circle, level color, card style.

import SwiftUI

struct LessonFrequencyStudentRow: View {
    let card: StudentFrequencyCard
    let targetRange: ClosedRange<Int>

    private var status: FrequencyStatus {
        FrequencyStatus.from(count: card.lessonCount, target: targetRange)
    }

    private var levelColor: Color {
        AppColors.color(forLevel: card.level)
    }

    private var initials: String {
        let first = card.firstName.prefix(1)
        let last = card.lastName.prefix(1)
        return "\(first)\(last)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if !card.subjectBreakdown.isEmpty {
                subjectBreakdownRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(CardStyle.strokeOpacity))
        )
        .shadow(color: CardStyle.shadowColor, radius: CardStyle.shadowRadius, y: 1)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            // Initial circle
            Text(initials)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(levelColor.gradient, in: Circle())

            // Name and level
            VStack(alignment: .leading, spacing: 1) {
                Text("\(card.firstName) \(card.lastName)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(card.level.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Lesson count with status indicator
            HStack(spacing: 6) {
                Text("\(card.lessonCount)")
                    .font(AppTheme.ScaledFont.header)
                    .fontWeight(.bold)
                    .foregroundStyle(status.color)

                Image(systemName: status.icon)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
        }
    }

    // MARK: - Subject Breakdown

    private var subjectBreakdownRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(card.subjectBreakdown) { subject in
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppColors.color(forSubject: subject.subject))
                        .frame(width: 6, height: 6)
                    Text(subject.subject)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(subject.count)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppColors.color(forSubject: subject.subject).opacity(0.1))
                )
            }
        }
    }

    // MARK: - Helpers

    private var cardBackground: Color {
        switch status {
        case .belowTarget:
            return CardStyle.cardBackgroundColor.opacity(1)
        default:
            return CardStyle.cardBackgroundColor
        }
    }
}

// Uses FlowLayout from Components/FlowLayout.swift
