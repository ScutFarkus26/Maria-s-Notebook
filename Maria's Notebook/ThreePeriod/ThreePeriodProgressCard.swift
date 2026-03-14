// ThreePeriodProgressCard.swift
// Horizontal bar showing lesson counts at each three-period stage.

import SwiftUI

struct ThreePeriodProgressCard: View {
    let counts: [ThreePeriodStage: Int]

    private var total: Int {
        counts.values.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(ThreePeriodStage.allCases) { stage in
                        let count = counts[stage, default: 0]
                        let fraction = total > 0 ? CGFloat(count) / CGFloat(total) : 0
                        if fraction > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(stage.color.gradient)
                                .frame(width: max(geo.size.width * fraction, 4))
                        }
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule(style: .continuous))

            // Legend
            HStack(spacing: 12) {
                ForEach(ThreePeriodStage.allCases) { stage in
                    let count = counts[stage, default: 0]
                    HStack(spacing: 3) {
                        Circle()
                            .fill(stage.color)
                            .frame(width: 6, height: 6)
                        Text("\(stage.shortName): \(count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}
