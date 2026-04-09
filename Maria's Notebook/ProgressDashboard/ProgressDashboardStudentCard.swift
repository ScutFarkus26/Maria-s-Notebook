// ProgressDashboardStudentCard.swift
// Card showing one student's active categories with prev/work/next.
// Design: Initial circle avatar, Things 3-style clean sections.

import SwiftUI

struct ProgressDashboardStudentCard: View {
    let card: StudentDashboardCard
    var onTapPreviousLesson: ((UUID) -> Void)?
    var onTapNextLesson: ((UUID) -> Void)?
    var onTapWork: ((UUID) -> Void)?
    /// Called with (lessonID, studentID) to add next lesson to inbox.
    var onAddToInbox: ((UUID, UUID) -> Void)?

    @State private var isExpanded = true

    private var levelColor: Color {
        card.level == .lower ? Color.green : Color.blue
    }

    private var initials: String {
        let first = card.firstName.prefix(1)
        let last = card.lastName.prefix(1)
        return "\(first)\(last)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded {
                categoryList
            }
        }
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

    // MARK: - Header

    private var headerRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                // Initial circle
                Text(initials)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(levelColor.gradient, in: Circle())

                // Name
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(card.firstName) \(card.lastName)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text(card.level.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)

                        Text("\(card.categories.count) active")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Categories

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(card.categories.enumerated()), id: \.element.id) { index, category in
                if index == 0 {
                    Divider()
                        .padding(.horizontal, 14)
                }

                ProgressDashboardCategoryRow(
                    category: category,
                    onTapPreviousLesson: {
                        if let assignmentID = category.previousLesson?.assignmentID {
                            onTapPreviousLesson?(assignmentID)
                        }
                    },
                    onTapNextLesson: {
                        if let assignmentID = category.nextLesson?.assignmentID {
                            onTapNextLesson?(assignmentID)
                        }
                    },
                    onTapWork: { workID in
                        onTapWork?(workID)
                    },
                    onScheduleNext: {
                        if let lessonID = category.nextLesson?.id {
                            onAddToInbox?(lessonID, card.id)
                        }
                    }
                )
                .padding(.horizontal, 14)

                if index < card.categories.count - 1 {
                    Divider()
                        .padding(.leading, 27)
                        .padding(.trailing, 14)
                }
            }
        }
        .padding(.bottom, 10)
    }
}
