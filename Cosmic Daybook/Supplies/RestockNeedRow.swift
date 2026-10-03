// RestockNeedRow.swift
// One need on the office run or the to-order list: a checkbox that checks it
// off, what it is, how many while it's still to request, and its link.

import SwiftUI
import CoreData

struct RestockNeedRow<Menu: View>: View {
    @ObservedObject var need: CDOrderItem
    /// The staple's level for a staple's need; nil for a one-off.
    let level: RestockLevel?
    /// The line under the name: the place and who marked it, the site, a note.
    let detail: String
    /// Nil once the need has been asked for (or checked off): the count is fixed.
    var onChangeQuantity: ((Int) -> Void)?
    /// Nil for a need already checked off.
    var onCheckOff: (() -> Void)?
    @ViewBuilder var menu: () -> Menu

    private var isReceived: Bool { need.receivedAt != nil }

    private var checkLabel: String {
        need.source == .office ? "Got \(need.displayTitle)" : "Received \(need.displayTitle)"
    }

    var body: some View {
        // Side by side when the name fits on one line; on a narrow row (an
        // iPhone, a long product name) the count drops under the name rather
        // than squeezing it.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                checkbox
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        title.lineLimit(1)
                        RestockTag(level: level)
                    }
                    detailText
                }
                Spacer(minLength: 6)
                quantityControl
                linkButton
            }
            HStack(alignment: .top, spacing: 10) {
                checkbox
                VStack(alignment: .leading, spacing: 4) {
                    title.lineLimit(3)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        RestockTag(level: level)
                        detailText
                    }
                    quantityControl
                }
                Spacer(minLength: 6)
                linkButton
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .surface(
            10,
            fill: CardStyle.cardBackgroundColor,
            stroke: Color.primary.opacity(0.08),
            lineWidth: 1,
            style: .continuous
        )
        .contentShape(Rectangle())
        .contextMenu { menu() }
    }

    private var checkbox: some View {
        Button {
            onCheckOff?()
        } label: {
            Image(systemName: isReceived ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isReceived ? AppColors.success : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onCheckOff == nil)
        .help(isReceived ? "Checked off" : "Check it off")
        .accessibilityLabel(isReceived ? "\(need.displayTitle), checked off" : checkLabel)
    }

    private var title: some View {
        Text(need.displayTitle)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isReceived ? .secondary : .primary)
    }

    @ViewBuilder
    private var detailText: some View {
        if !detail.isEmpty {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The count, unless it says nothing: a staple fetched from the office
    /// is fetched as "some".
    @ViewBuilder
    private var quantityControl: some View {
        if !(level != nil && need.source == .office) {
            OrderQuantityControl(quantity: Int(need.quantity), onChange: onChangeQuantity)
        }
    }

    @ViewBuilder
    private var linkButton: some View {
        if let url = need.url {
            Link(destination: url) {
                Image(systemName: "arrow.up.right.square")
                    .font(.title3)
                    .frame(minWidth: 28, minHeight: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open the link")
            .accessibilityLabel("Open link")
        }
    }
}
