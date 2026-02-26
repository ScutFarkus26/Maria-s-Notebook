// ProgressionLessonRow.swift
// Card component for each lesson in a student's progression timeline.

import SwiftUI

/// A lesson card in the student's subject/group timeline.
struct ProgressionLessonRow: View {
    let node: LessonProgressionNode
    let subjectColor: Color
    let onScheduleLesson: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status indicator column
            VStack(spacing: 0) {
                Circle()
                    .fill(node.status.color)
                    .frame(width: 14, height: 14)
                    .padding(.top, 4)

                if !node.isNext {
                    Rectangle()
                        .fill(node.status.color.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Lesson header
                HStack {
                    Text(node.lesson.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(node.status.color == .gray ? .secondary : .primary)

                    Spacer()

                    if let date = node.presentedAt {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if case .scheduled(let date) = node.status {
                        Text("Scheduled \(date, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Status label
                HStack(spacing: 4) {
                    Image(systemName: node.status.iconName)
                        .font(.caption2)
                    Text(node.status.label)
                        .font(.caption)
                }
                .foregroundStyle(node.status.color)

                // Work items
                if !node.activeWork.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(node.activeWork) { item in
                            workItemRow(item)
                        }
                    }
                    .padding(.top, 2)
                }

                // Action button
                if node.isNext, let action = onScheduleLesson {
                    Button {
                        action()
                    } label: {
                        Label("Schedule Lesson", systemImage: SFSymbol.Time.calendar)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(subjectColor)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Work Item Row

    private func workItemRow(_ item: WorkProgressItem) -> some View {
        HStack(spacing: 6) {
            // Kind badge
            if let kind = item.kind {
                Text(kind.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(kind.color.opacity(0.15)))
                    .foregroundStyle(kind.color)
            }

            // Age
            Text("\(item.ageSchoolDays) school days")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Status
            Text(item.status.rawValue)
                .font(.caption2)
                .foregroundStyle(item.status.color)

            Spacer()

            // Check-in indicators
            if let next = item.nextCheckIn {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Check-in \(next.date, style: .date)")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
    }
}
