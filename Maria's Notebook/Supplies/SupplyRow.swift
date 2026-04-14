import SwiftUI
import CoreData

/// A row displaying a supply item
struct SupplyRow: View {
    let supply: CDSupply
    var onQuickAdjust: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: supply.category.icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            // Supply info
            VStack(alignment: .leading, spacing: 2) {
                Text(supply.name)
                    .font(.headline)
                    .lineLimit(1)

                if !supply.location.isEmpty {
                    Label(supply.location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Quantity and quick adjust
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
                Text("\(supply.currentQuantity)")
                    .font(.title2.weight(.semibold))
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
                .stroke(Color.primary.opacity(CardStyle.strokeOpacity), lineWidth: 1)
        )
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

    let s2 = CDSupply(context: ctx)
    s2.name = "Safety Scissors"
    s2.category = .art
    s2.location = "Drawer 2"
    s2.currentQuantity = 4

    let s3 = CDSupply(context: ctx)
    s3.name = "Number Rods"
    s3.category = .math
    s3.location = "Shelf B3"
    s3.currentQuantity = 0

    return VStack(spacing: 12) {
        SupplyRow(supply: s1)
        SupplyRow(supply: s2)
        SupplyRow(supply: s3)
    }
    .padding()
    .previewEnvironment(using: stack)
}
