// OrderItemRow.swift
// One order: a received checkbox, what it is, and where it stands.

import SwiftUI
import CoreData

struct OrderItemRow: View {
    @ObservedObject var item: CDOrderItem
    /// Nil once the item has been asked for: the office already has the number.
    var onChangeQuantity: ((Int) -> Void)?
    var onToggleReceived: (Bool) -> Void

    private var isReceived: Bool { item.stage == .received }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onToggleReceived(!isReceived)
            } label: {
                Image(systemName: isReceived ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isReceived ? AppColors.success : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(isReceived ? "Mark as not received" : "Check off as received")
            .accessibilityLabel(isReceived ? "Received" : "Not received")
            .accessibilityHint(isReceived ? "Marks this item as not received" : "Checks this item off as received")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.headline)
                    .foregroundStyle(isReceived ? .secondary : .primary)
                    .lineLimit(2)

                if let caption = item.linkCaption {
                    Label(caption, systemImage: "link")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let status = statusLine {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            OrderQuantityControl(quantity: Int(item.quantity), onChange: onChangeQuantity)

            if let url = item.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open the link")
                .accessibilityLabel("Open link")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .surface(
            CardStyle.cornerRadius,
            fill: CardStyle.cardBackgroundColor,
            stroke: Color.primary.opacity(CardStyle.strokeOpacity),
            lineWidth: 1,
            style: .continuous
        )
    }

    /// When the item reached its current stage. Asked-for items show nothing:
    /// their request's header already carries the date.
    private var statusLine: String? {
        let format = DateFormatters.shortMonthDay
        switch item.stage {
        case .toRequest:
            return item.createdAt.map { "Added \(format.string(from: $0))" }
        case .requested:
            return nil
        case .confirmed:
            guard let confirmed = item.confirmedAt else { return nil }
            var line = "Confirmed \(format.string(from: confirmed))"
            if let asked = item.requestedAt {
                line += " · asked \(format.string(from: asked))"
            }
            return line
        case .received:
            return item.receivedAt.map { "Received \(format.string(from: $0))" }
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct OrderItemRowPreview: View {
    var body: some View {
        let stack = CoreDataStack.preview
        let ctx = stack.viewContext

        let pencils = CDOrderItem(context: ctx)
        pencils.urlString = "https://www.example.com/colored-pencils"
        pencils.title = "Colored Pencils, 24 count"
        pencils.quantity = 2

        let rods = CDOrderItem(context: ctx)
        rods.urlString = "https://www.example.com/number-rods"
        rods.title = "Number Rods replacement set"
        rods.requestedAt = Date().addingTimeInterval(-3 * 86_400)
        rods.confirmedAt = Date().addingTimeInterval(-86_400)
        rods.notes = "The red and blue set"

        return VStack(spacing: 12) {
            OrderItemRow(item: pencils) { _ in }
            OrderItemRow(item: rods) { _ in }
        }
        .padding()
        .previewEnvironment(using: stack)
    }
}

#Preview {
    OrderItemRowPreview()
}
