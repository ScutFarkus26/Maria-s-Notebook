import SwiftUI
import CoreData

/// A row displaying a supply item with status indicators
struct SupplyRow: View {
    let supply: CDSupply
    var onQuickAdjust: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: supply.category.icon)
                .font(.title3)
                .foregroundStyle(supply.status.color)
                .frame(width: 32)

            // CDSupply info
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
                if let onQuickAdjust {
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
                        .foregroundStyle(supply.status.color)

                    Text(supply.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 50, alignment: .trailing)

                if let onQuickAdjust {
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

                if supply.isOnOrder {
                    Label("Ordered", systemImage: "shippingbox.fill")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(UIConstants.OpacityConstants.accent)))
                        .foregroundStyle(.blue)
                }
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
                .background(Capsule().fill(AppColors.warning.opacity(UIConstants.OpacityConstants.accent)))
                .foregroundStyle(AppColors.warning)
        case .critical:
            Label("Critical", systemImage: "exclamationmark.circle.fill")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppColors.destructive.opacity(UIConstants.OpacityConstants.accent)))
                .foregroundStyle(AppColors.destructive)
        case .outOfStock:
            Label("Out", systemImage: "xmark.circle.fill")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppColors.destructive.opacity(UIConstants.OpacityConstants.accent)))
                .foregroundStyle(AppColors.destructive)
        }
    }

    private var borderColor: Color {
        switch supply.status {
        case .healthy:
            return Color.primary.opacity(CardStyle.strokeOpacity)
        case .low:
            return Color.orange.opacity(UIConstants.OpacityConstants.semi)
        case .critical, .outOfStock:
            return Color.red.opacity(UIConstants.OpacityConstants.semi)
        }
    }

}

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext

    let s1 = CDSupply(context: ctx)
    s1.name = "Crayons (24-pack)"
    s1.category = .art
    s1.location = "Cabinet A"
    s1.currentQuantity = 12
    s1.minimumThreshold = 5
    s1.unit = "boxes"

    let s2 = CDSupply(context: ctx)
    s2.name = "Safety Scissors"
    s2.category = .art
    s2.location = "Drawer 2"
    s2.currentQuantity = 4
    s2.minimumThreshold = 10
    s2.unit = "pairs"

    let s3 = CDSupply(context: ctx)
    s3.name = "Number Rods"
    s3.category = .math
    s3.location = "Shelf B3"
    s3.currentQuantity = 0
    s3.minimumThreshold = 2
    s3.unit = "sets"

    return VStack(spacing: 12) {
        SupplyRow(supply: s1)
        SupplyRow(supply: s2)
        SupplyRow(supply: s3)
    }
    .padding()
    .previewEnvironment(using: stack)
}
