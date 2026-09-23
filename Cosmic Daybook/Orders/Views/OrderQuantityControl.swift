// OrderQuantityControl.swift
// How many of an item to ask for: − count + on a row, the same shape as a
// supply's quick adjust. Read-only once the office has been asked.

import SwiftUI

struct OrderQuantityControl: View {
    let quantity: Int
    /// Nil shows the count without buttons — the request has already gone out.
    var onChange: ((Int) -> Void)?

    private static var range: ClosedRange<Int> { OrderService.quantityRange }

    var body: some View {
        if let onChange {
            HStack(spacing: 6) {
                Button {
                    onChange(quantity - 1)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(quantity <= Self.range.lowerBound)
                .help("One fewer")

                Text("\(quantity)")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 24)

                Button {
                    onChange(quantity + 1)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(quantity >= Self.range.upperBound)
                .help("One more")
            }
            .accessibilityElement()
            .accessibilityLabel("Quantity")
            .accessibilityValue("\(quantity)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onChange(min(quantity + 1, Self.range.upperBound))
                case .decrement: onChange(max(quantity - 1, Self.range.lowerBound))
                @unknown default: break
                }
            }
        } else {
            Text("Qty \(quantity)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Quantity \(quantity)")
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct OrderQuantityControlPreview: View {
    @State private var quantity = 2

    var body: some View {
        VStack(spacing: 16) {
            OrderQuantityControl(quantity: quantity) { quantity = $0 }
            OrderQuantityControl(quantity: 3)
        }
        .padding()
    }
}

#Preview {
    OrderQuantityControlPreview()
}
