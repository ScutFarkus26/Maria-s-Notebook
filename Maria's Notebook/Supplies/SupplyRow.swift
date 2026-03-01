import SwiftUI
import SwiftData

/// A row displaying a supply item with status indicators
struct SupplyRow: View {
    let supply: Supply
    var onQuickAdjust: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: supply.category.icon)
                .font(.title3)
                .foregroundStyle(colorForStatus(supply.status))
                .frame(width: 32)

            // Supply info
            VStack(alignment: .leading, spacing: 2) {
                Text(supply.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !supply.location.isEmpty {
                        Label(supply.location, systemImage: "mappin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if supply.minimumThreshold > 0 {
                        Text("Min: \(supply.minimumThreshold)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Quantity and status
            HStack(spacing: 8) {
                if let onQuickAdjust = onQuickAdjust {
                    // Quick adjust buttons
                    Button {
                        onQuickAdjust(-1)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(supply.currentQuantity <= 0)
                }

                // Quantity display
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(supply.currentQuantity)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(colorForStatus(supply.status))

                    Text(supply.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 50, alignment: .trailing)

                if let onQuickAdjust = onQuickAdjust {
                    Button {
                        onQuickAdjust(1)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                // Status indicator
                statusBadge
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .fill(CardStyle.cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch supply.status {
        case .healthy:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.success)
        case .low:
            Label("Low", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppColors.warning.opacity(0.15)))
                .foregroundStyle(AppColors.warning)
        case .critical:
            Label("Critical", systemImage: "exclamationmark.circle.fill")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppColors.destructive.opacity(0.15)))
                .foregroundStyle(AppColors.destructive)
        case .outOfStock:
            Label("Out", systemImage: "xmark.circle.fill")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppColors.destructive.opacity(0.15)))
                .foregroundStyle(AppColors.destructive)
        }
    }

    private var borderColor: Color {
        switch supply.status {
        case .healthy:
            return Color.primary.opacity(CardStyle.strokeOpacity)
        case .low:
            return Color.orange.opacity(0.3)
        case .critical, .outOfStock:
            return Color.red.opacity(0.3)
        }
    }

    private func colorForStatus(_ status: SupplyStatus) -> Color {
        switch status {
        case .healthy: return .primary
        case .low: return .orange
        case .critical, .outOfStock: return .red
        }
    }
}

/// A compact row for supply lists
struct SupplyCompactRow: View {
    let supply: Supply

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: supply.category.icon)
                .foregroundStyle(colorForStatus(supply.status))

            Text(supply.name)
                .lineLimit(1)

            Spacer()

            Text("\(supply.currentQuantity)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(colorForStatus(supply.status))

            Image(systemName: supply.status.icon)
                .font(.caption)
                .foregroundStyle(colorForStatus(supply.status))
        }
    }

    private func colorForStatus(_ status: SupplyStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .low: return .orange
        case .critical, .outOfStock: return .red
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        SupplyRow(
            supply: Supply(
                name: "Crayons (24-pack)",
                category: .art,
                location: "Cabinet A",
                currentQuantity: 12,
                minimumThreshold: 5,
                unit: "boxes"
            )
        )

        SupplyRow(
            supply: Supply(
                name: "Safety Scissors",
                category: .art,
                location: "Drawer 2",
                currentQuantity: 4,
                minimumThreshold: 10,
                unit: "pairs"
            )
        )

        SupplyRow(
            supply: Supply(
                name: "Number Rods",
                category: .math,
                location: "Shelf B3",
                currentQuantity: 0,
                minimumThreshold: 2,
                unit: "sets"
            )
        )
    }
    .padding()
}
