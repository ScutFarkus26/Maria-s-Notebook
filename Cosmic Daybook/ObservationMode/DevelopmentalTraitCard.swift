// DevelopmentalTraitCard.swift
// Card showing a single developmental characteristic with observation count and recency.

import SwiftUI

struct DevelopmentalTraitCard: View {
    let data: DevelopmentalTraitCardData

    private var characteristic: DevelopmentalCharacteristic {
        data.characteristic
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: characteristic.icon)
                .font(.title3)
                .foregroundStyle(characteristic.color)
                .frame(width: 36, height: 36)
                .background(
                    characteristic.color.opacity(UIConstants.OpacityConstants.medium),
                    in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                )

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(characteristic.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(characteristic.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Count and recency
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(data.observationCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(data.observationCount > 0 ? .primary : .quaternary)

                if let date = data.mostRecentDate {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .surface(
            CardStyle.cornerRadius,
            fill: CardStyle.cardBackgroundColor,
            stroke: Color.primary.opacity(CardStyle.strokeOpacity),
            style: .continuous
        )
        .shadow(color: CardStyle.shadowColor, radius: CardStyle.shadowRadius, y: 1)
    }
}
