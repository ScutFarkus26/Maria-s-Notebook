// ProgressDashboardCategoryRow.swift
// A single subject › group row showing previous → next lesson flow with open work.
// Design: Flighty-inspired departure→arrival flow, Linear's minimal chrome.

import SwiftUI

struct ProgressDashboardCategoryRow: View {
    let category: StudentCategoryProgress
    var onTapPreviousLesson: (() -> Void)?
    var onTapNextLesson: (() -> Void)?
    var onTapWork: ((UUID) -> Void)?

    private var subjectColor: Color {
        AppColors.color(forSubject: category.subject)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Leading subject color accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(subjectColor)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                categoryHeader
                lessonFlow
                workSection
            }
            .padding(.leading, 10)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Header

    private var categoryHeader: some View {
        HStack(spacing: 5) {
            Text(category.subject)
                .fontWeight(.semibold)
                .foregroundStyle(subjectColor)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(subjectColor.opacity(UIConstants.OpacityConstants.half))

            Text(category.group)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    // MARK: - CDLesson Flow (prev → next)

    private var lessonFlow: some View {
        HStack(alignment: .top, spacing: 0) {
            // Previous lesson
            previousColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            // Flow arrow
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 8)
                .padding(.top, 3)

            // Next lesson
            nextColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previousColumn: some View {
        Group {
            if let prev = category.previousLesson {
                Button {
                    onTapPreviousLesson?()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prev.name)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(prev.presentedAt, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("No lessons yet")
                    .font(.footnote)
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private var nextColumn: some View {
        Group {
            if let next = category.nextLesson {
                Button {
                    onTapNextLesson?()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.name)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        nextLessonStateBadge(next.state)
                    }
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("End of sequence")
                        .font(.footnote)
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }

    // MARK: - Work

    @ViewBuilder
    private var workSection: some View {
        if !category.openWork.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(category.openWork) { work in
                    Button {
                        onTapWork?(work.id)
                    } label: {
                        workCapsule(work)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func workCapsule(_ work: OpenWorkSummary) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(work.kind?.color ?? .gray)
                .frame(width: 5, height: 5)

            if let kind = work.kind {
                Text(kind.displayName)
                    .fontWeight(.medium)
                    .foregroundStyle(kind.color)
            }

            Text(work.title)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(work.ageSchoolDays)d")
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
    }

    // MARK: - State Badge

    @ViewBuilder
    private func nextLessonStateBadge(_ state: NextLessonState) -> some View {
        switch state {
        case .notPlanned:
            Text("Not planned")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        case .inInbox:
            Label("Inbox", systemImage: "tray")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
        case .scheduled(let date):
            Label {
                Text(date, format: .dateTime.month(.abbreviated).day())
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.orange)
        }
    }
}
