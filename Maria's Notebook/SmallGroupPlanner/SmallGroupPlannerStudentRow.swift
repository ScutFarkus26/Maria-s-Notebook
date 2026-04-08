// SmallGroupPlannerStudentRow.swift
// Reusable student row with checkbox, initials, name, level badge, and blocking reason capsules.

import SwiftUI

struct SmallGroupPlannerStudentRow: View {
    let student: GroupStudentStatus
    let isSelected: Bool
    let onToggle: () -> Void
    var onConfirmMastery: ((UUID) -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            // Selection checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? student.tier.color : .secondary)
            }
            .buttonStyle(.plain)

            // Tier accent bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(student.tier.color.gradient)
                .frame(width: 3, height: 32)

            // Initials circle
            Text(student.initials)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    AppColors.color(forLevel: student.level).gradient,
                    in: Circle()
                )

            // Name + level
            VStack(alignment: .leading, spacing: 2) {
                Text(student.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(student.level.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Blocking reasons
            if !student.blockingReasons.isEmpty {
                blockingReasonCapsules
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    // MARK: - Blocking Reasons

    private var blockingReasonCapsules: some View {
        let reasons = student.blockingReasons
        return VStack(alignment: .trailing, spacing: 4) {
            ForEach(reasons) { reason in
                blockingReasonCapsule(reason)
            }
        }
    }

    private func blockingReasonCapsule(_ reason: GroupBlockingReason) -> some View {
        HStack(spacing: 4) {
            Image(systemName: reason.icon)
                .font(.system(size: 9))

            Text(reason.summary)
                .font(.system(size: 9))
                .lineLimit(1)

            if case .needsTeacherConfirmation(_, let assignmentID) = reason {
                Button {
                    onConfirmMastery?(assignmentID)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11))
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
        .foregroundStyle(reason.isActionable ? AnyShapeStyle(.white) : AnyShapeStyle(reason.color))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(reason.isActionable
                      ? AnyShapeStyle(reason.color.gradient)
                      : AnyShapeStyle(reason.color.opacity(UIConstants.OpacityConstants.light))
                )
        )
    }
}
