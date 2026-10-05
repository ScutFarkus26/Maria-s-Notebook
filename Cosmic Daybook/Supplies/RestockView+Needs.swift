// RestockView+Needs.swift
// The two lists: the office run, and to order with Draft Request, the
// "Requests go to" nudge, and the Asked For and Received folds.

import SwiftUI
import CoreData

extension RestockView {

    func needsSection(digest: RestockDigest, staplesByID: [String: CDSupply]) -> some View {
        let layout = isCompact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Needs", detail: digest.headerLine)
            layout {
                officeRunCard(staplesByID: staplesByID)
                toOrderCard(staplesByID: staplesByID)
            }
        }
    }

    func sectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Office run

    private func officeRunCard(staplesByID: [String: CDSupply]) -> some View {
        let run = officeRun
        return needsCard(title: "Office run", icon: "building.2", count: run.count) {
            EmptyView()
        } content: {
            if run.isEmpty {
                emptyLine("Nothing to fetch. The shelf is stocked.")
            } else {
                ForEach(run, id: \.objectID) { need in
                    row(need, staplesByID: staplesByID)
                }
            }
            Text("Check things off as you bring them back. A staple goes back to Stocked.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    // MARK: - To order

    private func toOrderCard(staplesByID: [String: CDSupply]) -> some View {
        let waiting = toRequest
        let asked = askedFor
        let confirmedNeeds = confirmed
        let askedCount = asked.reduce(0) { $0 + $1.items.count } + confirmedNeeds.count
        return needsCard(title: "To order", icon: "cart", count: waiting.count) {
            Button("Draft Request") { showingDraft = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(waiting.isEmpty)
                .help("Write the office one email asking for everything not yet asked for")
        } content: {
            if !OrderRequestRecipient(name: "", email: recipientEmail).isConfigured {
                recipientNudge
            }
            if waiting.isEmpty {
                emptyLine(askedCount == 0 ? "Nothing to order." : "Nothing new to ask for.")
            } else {
                ForEach(waiting, id: \.objectID) { need in
                    row(need, staplesByID: staplesByID)
                }
            }
            Divider().padding(.top, 4)
            askedForFold(asked: asked, confirmed: confirmedNeeds, count: askedCount, staplesByID: staplesByID)
            receivedFold(staplesByID: staplesByID)
        }
    }

    private var recipientNudge: some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.badge")
                .foregroundStyle(RestockStyle.lowText)
            Text("Requests go to: not set")
                .font(.caption)
                .foregroundStyle(RestockStyle.lowText)
            Spacer(minLength: 6)
            Button("Set Up…") { showingSettings = true }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .surface(9, fill: RestockStyle.lowFill, stroke: RestockStyle.lowStroke.opacity(0.6), style: .continuous)
    }

    private func askedForFold(
        asked: [OrderRequestGroup],
        confirmed: [CDOrderItem],
        count: Int,
        staplesByID: [String: CDSupply]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            foldHeader(
                title: "Asked for",
                summary: count == 0 ? "none waiting" : "\(count) waiting",
                isOpen: $showingAskedFor,
                isEnabled: count > 0
            )
            if showingAskedFor && count > 0 {
                ForEach(asked) { request in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Self.requestLine(request))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Mark Confirmed") { markConfirmed(request.items) }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .help("The office confirmed they got this request")
                    }
                    ForEach(request.items, id: \.objectID) { need in
                        row(need, staplesByID: staplesByID)
                    }
                }
                if !confirmed.isEmpty {
                    Text("Confirmed: check each one off when it arrives")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(confirmed, id: \.objectID) { need in
                        row(need, staplesByID: staplesByID)
                    }
                }
            }
        }
    }

    private func receivedFold(staplesByID: [String: CDSupply]) -> some View {
        let done = received
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                foldHeader(
                    title: "Received", summary: "\(done.count)", isOpen: $showingReceived, isEnabled: !done.isEmpty
                )
                if showingReceived && !done.isEmpty {
                    Button("Clear Received…") { confirmingClearReceived = true }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            if showingReceived {
                ForEach(done, id: \.objectID) { need in
                    row(need, staplesByID: staplesByID)
                }
            }
        }
    }

    private func foldHeader(title: String, summary: String, isOpen: Binding<Bool>, isEnabled: Bool) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isOpen.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isOpen.wrappedValue && isEnabled ? 90 : 0))
                Text("\(title) · \(summary)")
                    .font(.caption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityHint(isOpen.wrappedValue ? "Hides them" : "Shows them")
    }

    /// "Asked Sep 30 · Ms. Levin · waiting 3 days".
    static func requestLine(_ request: OrderRequestGroup, now: Date = Date()) -> String {
        var parts: [String] = []
        if let date = request.requestedAt {
            parts.append("Asked \(DateFormatters.shortMonthDay.string(from: date))")
        } else {
            parts.append("Asked for")
        }
        if !request.requestedFrom.isEmpty { parts.append(request.requestedFrom) }
        if let date = request.requestedAt {
            let days = AppCalendar.shared.dateComponents(
                [.day],
                from: AppCalendar.shared.startOfDay(for: date),
                to: AppCalendar.shared.startOfDay(for: now)
            ).day ?? 0
            switch days {
            case ..<1: parts.append("waiting since today")
            case 1: parts.append("waiting 1 day")
            default: parts.append("waiting \(days) days")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Rows

    func row(_ need: CDOrderItem, staplesByID: [String: CDSupply]) -> some View {
        let staple = need.supplyID.flatMap { staplesByID[$0.uppercased()] }
        return RestockNeedRow(
            need: need,
            level: need.isStapleNeed ? (staple?.level ?? .low) : nil,
            detail: detail(for: need, staple: staple),
            onChangeQuantity: need.stage == .toRequest ? { setQuantity(need, $0) } : nil,
            onCheckOff: need.receivedAt == nil ? { checkOff(need) } : nil
        ) {
            needMenu(need, staple: staple)
        }
    }

    /// The line under a need's name: where a staple lives and who marked it,
    /// or a one-off's site, note and who added it. Who shows only when it
    /// isn't the person looking.
    func detail(for need: CDOrderItem, staple: CDSupply?) -> String {
        var parts: [String] = []
        if let staple {
            if !staple.location.trimmed().isEmpty { parts.append(staple.location.trimmed()) }
            if need.source == .order, need.url == nil { parts.append("No link yet") }
            if !staple.notes.isEmpty { parts.append(staple.notes) }
            let by = byLine(for: staple)
            if !by.isEmpty { parts.append(by) }
            return parts.isEmpty ? "Staple" : parts.joined(separator: " · ")
        }
        if let caption = need.linkCaption { parts.append(caption) }
        if !need.notes.isEmpty { parts.append(need.notes) }
        if let added = Self.addedByLine(changedByID: need.addedByID, name: need.addedByName, viewer: author) {
            parts.append(added)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Who, when it isn't you

    /// Who made a change, as `viewer` reads it, or nil when it was `viewer`
    /// (your own changes carry no label) or the change has no stamp at all.
    static func someoneElse(changedByID id: String?, name: String?, viewer: RestockAuthor) -> String? {
        let name = name?.trimmed() ?? ""
        guard id != nil || !name.isEmpty else { return nil }
        let who = viewer.reads(changedByID: id, name: name)
        return who == "You" ? nil : who
    }

    /// "added by Rivka" on a one-off someone else added; nil on your own.
    static func addedByLine(changedByID id: String?, name: String?, viewer: RestockAuthor) -> String? {
        someoneElse(changedByID: id, name: name, viewer: viewer).map { "added by \($0)" }
    }

    @ViewBuilder
    private func needMenu(_ need: CDOrderItem, staple: CDSupply?) -> some View {
        if let url = need.url {
            Link(destination: url) {
                Label("Open Link", systemImage: "safari")
            }
            Button("Copy Link", systemImage: "doc.on.doc") { Pasteboard.copy(need.urlString) }
        }
        if let staple {
            Button("Edit Staple…", systemImage: "pencil") { stapleSheet = .edit(staple) }
        } else {
            Button("Edit…", systemImage: "pencil") { editingNeed = need }
        }
        if need.source == .order {
            Divider()
            switch need.stage {
            case .toRequest:
                Button("Mark Asked For", systemImage: OrderStage.requested.icon) { markAskedFor([need]) }
            case .requested:
                Button("Mark Confirmed", systemImage: OrderStage.confirmed.icon) { markConfirmed([need]) }
            case .confirmed:
                Button("Not Confirmed Yet", systemImage: "arrow.uturn.backward") { clearConfirmation([need]) }
            case .received:
                EmptyView()
            }
            if need.stage == .requested || need.stage == .confirmed {
                Button("Move Back to To Order", systemImage: "arrow.uturn.backward.circle") {
                    moveBackToRequest([need])
                }
            }
        }
        Divider()
        Button("Remove", systemImage: "trash", role: .destructive) { removeNeeds([need]) }
    }

    // MARK: - Building blocks

    private func needsCard<Trailing: View, Content: View>(
        title: String,
        icon: String,
        count: Int,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.bottom, 2)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .surface(
            RestockStyle.tileRadius,
            fill: Color.primary.opacity(0.025),
            stroke: Color.primary.opacity(0.1),
            lineWidth: 1,
            style: .continuous
        )
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
}
