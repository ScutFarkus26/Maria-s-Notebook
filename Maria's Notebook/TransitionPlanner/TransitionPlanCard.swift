// TransitionPlanCard.swift
// Summary card for a transition plan in the list view.

import SwiftUI

struct TransitionPlanCard: View {
    let plan: TransitionPlan
    let viewModel: TransitionPlannerViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Student avatar
            if let student = viewModel.student(for: plan) {
                Text("\(student.firstName.prefix(1))\(student.lastName.prefix(1))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(AppColors.color(forLevel: student.level).gradient, in: Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                // Name
                if let student = viewModel.student(for: plan) {
                    Text("\(student.firstName) \(student.lastName)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                // Level transition
                HStack(spacing: 4) {
                    Text(plan.fromLevelRaw)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(plan.toLevelRaw)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Progress
            VStack(alignment: .trailing, spacing: 4) {
                let pct = viewModel.readinessPercentage(for: plan)
                Text("\(Int(pct * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(pct >= 1.0 ? .green : Color.accentColor)

                // Status badge
                HStack(spacing: 3) {
                    Image(systemName: plan.status.icon)
                        .font(.system(size: 8))
                    Text(plan.status.displayName)
                        .font(.caption2)
                }
                .foregroundStyle(plan.status.color)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                    Capsule(style: .continuous)
                        .fill(viewModel.readinessPercentage(for: plan) >= 1.0
                              ? Color.green.gradient
                              : Color.accentColor.gradient)
                        .frame(width: geo.size.width * viewModel.readinessPercentage(for: plan))
                }
            }
            .frame(width: 60, height: 6)
        }
        .cardStyle()
    }
}
