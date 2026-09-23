// OrdersView+Sections.swift
// The drop zone and the four stages, split out to keep OrdersView within
// SwiftLint's type-body limit.

import SwiftUI
import CoreData

extension OrdersView {

    // MARK: - Drop Zone

    var addLinkZone: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.title2)
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag a link here")
                        .font(.headline)
                    Text("From Safari or any browser — or paste one below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("https://…", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled(true)
                    .onSubmit(addTypedLink)
                Button("Add", action: addTypedLink)
                    .disabled(linkText.trimmed().isEmpty)
                PasteButton(payloadType: String.self) { strings in
                    addPasted(strings)
                }
                .labelStyle(.iconOnly)
                .help("Paste a copied link")
            }

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: [6, 4])
                )
        )
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }

    // MARK: - Stages

    @ViewBuilder
    var toRequestSection: some View {
        if !toRequest.isEmpty {
            stageSection(
                title: OrderStage.toRequest.displayName,
                icon: OrderStage.toRequest.icon,
                subtitle: "Not asked for yet",
                items: toRequest
            ) {
                Button {
                    showingDraft = true
                } label: {
                    Label("Draft Request", systemImage: "envelope")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    func requestSection(_ request: OrderRequestGroup) -> some View {
        stageSection(
            title: requestTitle(request),
            icon: OrderStage.requested.icon,
            subtitle: requestSubtitle(request),
            items: request.items
        ) {
            Button {
                markConfirmed(request.items)
            } label: {
                Label("Mark Confirmed", systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("The office confirmed they got this request")
        }
    }

    @ViewBuilder
    var confirmedSection: some View {
        if !confirmed.isEmpty {
            stageSection(
                title: OrderStage.confirmed.displayName,
                icon: OrderStage.confirmed.icon,
                subtitle: "Check each one off when it arrives",
                items: confirmed
            ) {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    var receivedSection: some View {
        if !received.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showingReceived.toggle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: OrderStage.received.icon)
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(OrderStage.received.displayName)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("\(received.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showingReceived ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(showingReceived ? "Hides received items" : "Shows received items")

                    Spacer()

                    if showingReceived {
                        Button("Clear Received…") {
                            confirmingClearReceived = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 8)

                if showingReceived {
                    rows(received)
                }
            }
        }
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cart")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Nothing to Order")
                .font(.title2.weight(.semibold))
            Text("Drop a link to something your classroom needs. When you're ready, "
                 + "Draft Request writes the office one email asking for all of it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Building Blocks

    func stageSection<Trailing: View>(
        title: String,
        icon: String,
        subtitle: String,
        items: [CDOrderItem],
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let heading = HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text("\(items.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        let action = trailing().fixedSize()

        return VStack(alignment: .leading, spacing: 12) {
            // Side by side when it fits; on an iPhone the button drops under
            // the heading rather than wrapping its label onto two lines.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    heading
                    Spacer(minLength: 12)
                    action
                }
                VStack(alignment: .leading, spacing: 8) {
                    heading
                    action
                }
            }
            .padding(.top, 8)

            rows(items)
        }
    }

    func rows(_ items: [CDOrderItem]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                OrderItemRow(
                    item: item,
                    onChangeQuantity: item.stage == .toRequest ? { setQuantity(item, $0) } : nil
                ) { received in
                    setReceived(item, received)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editingItem = item
                }
                .contextMenu {
                    rowMenu(item)
                }
            }
        }
    }

    @ViewBuilder
    func rowMenu(_ item: CDOrderItem) -> some View {
        if let url = item.url {
            Link(destination: url) {
                Label("Open Link", systemImage: "safari")
            }
            Button {
                Pasteboard.copy(item.urlString)
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
        }
        Button {
            editingItem = item
        } label: {
            Label("Edit…", systemImage: "pencil")
        }

        Divider()

        stageMenuItems(item)

        Divider()

        Button(role: .destructive) {
            delete([item])
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// The moves that make sense from where the item stands now.
    @ViewBuilder
    private func stageMenuItems(_ item: CDOrderItem) -> some View {
        switch item.stage {
        case .toRequest:
            Button {
                markAskedFor([item])
            } label: {
                Label("Mark Asked For", systemImage: OrderStage.requested.icon)
            }
        case .requested:
            Button {
                markConfirmed([item])
            } label: {
                Label("Mark Confirmed", systemImage: OrderStage.confirmed.icon)
            }
        case .confirmed:
            Button {
                clearConfirmation([item])
            } label: {
                Label("Not Confirmed Yet", systemImage: "arrow.uturn.backward")
            }
        case .received:
            EmptyView()
        }
        Button {
            setReceived(item, item.stage != .received)
        } label: {
            item.stage == .received
                ? Label("Not Received", systemImage: "circle")
                : Label("Mark Received", systemImage: "checkmark.circle")
        }
        if item.stage != .toRequest {
            Button {
                moveBackToRequest([item])
            } label: {
                Label("Move Back to To Request", systemImage: "arrow.uturn.backward.circle")
            }
        }
    }

    // MARK: - Request Headers

    private func requestTitle(_ request: OrderRequestGroup) -> String {
        guard let date = request.requestedAt else { return OrderStage.requested.displayName }
        return "Asked \(DateFormatters.shortMonthDay.string(from: date))"
    }

    private func requestSubtitle(_ request: OrderRequestGroup) -> String {
        var parts: [String] = []
        if !request.requestedFrom.isEmpty {
            parts.append("Sent to \(request.requestedFrom)")
        }
        if let date = request.requestedAt {
            let days = AppCalendar.shared.dateComponents(
                [.day],
                from: AppCalendar.shared.startOfDay(for: date),
                to: AppCalendar.shared.startOfDay(for: Date())
            ).day ?? 0
            switch days {
            case ..<1: parts.append("waiting since today")
            case 1: parts.append("waiting 1 day")
            default: parts.append("waiting \(days) days")
            }
        }
        return parts.isEmpty ? "Waiting for the office to confirm" : parts.joined(separator: " · ")
    }
}
