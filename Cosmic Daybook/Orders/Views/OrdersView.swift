// OrdersView.swift
// Things to ask the office to order: drop a link in, send one request for
// everything not yet asked for, then follow each item through confirmed and
// received.

import SwiftUI
import CoreData

struct OrdersView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(SaveCoordinator.self) var saveCoordinator
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDOrderItem.createdAt, ascending: true)
    ]) var itemsRaw: FetchedResults<CDOrderItem>

    @State var linkText = ""
    @State var isDropTargeted = false
    @State var notice: String?
    @State var showingDraft = false
    @State var showingSettings = false
    @State var editingItem: CDOrderItem?
    @State var showingReceived = false
    @State var confirmingClearReceived = false
    /// Pending save for −/+ taps, so tapping up to 6 is one save (and one
    /// CloudKit push), not five.
    @State var quantitySave: Task<Void, Never>?

    var items: [CDOrderItem] { Array(itemsRaw) }

    var toRequest: [CDOrderItem] { items.filter { $0.stage == .toRequest } }

    var openRequests: [OrderRequestGroup] { OrderService.openRequests(items) }

    var confirmed: [CDOrderItem] {
        items.filter { $0.stage == .confirmed }
            .sorted { ($0.confirmedAt ?? .distantPast) < ($1.confirmedAt ?? .distantPast) }
    }

    var received: [CDOrderItem] {
        items.filter { $0.stage == .received }
            .sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            // Draft Request sits on the To Request section, so the header keeps
            // only the settings gear and fits an iPhone's width.
            ViewHeader(title: "Orders") {
                settingsButton
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Divider()
            #endif

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    addLinkZone

                    if items.isEmpty {
                        emptyState
                    } else {
                        toRequestSection
                        ForEach(openRequests) { request in
                            requestSection(request)
                        }
                        confirmedSection
                        receivedSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        // The whole screen takes a dropped link, not just the drop zone.
        .dropDestination(for: URL.self) { urls, _ in
            addLinks(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .sheet(isPresented: $showingDraft) {
            OrderRequestDraftSheet(items: toRequest)
        }
        .sheet(isPresented: $showingSettings) {
            OrderRequestSettingsSheet()
        }
        .sheet(item: $editingItem) { item in
            OrderItemEditSheet(item: item)
        }
        .confirmationDialog(
            "Remove \(received.count) received \(received.count == 1 ? "item" : "items")?",
            isPresented: $confirmingClearReceived,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { clearReceived() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They are deleted from Orders on all your devices.")
        }
        .onDisappear(perform: flushQuantitySave)
        .navigationTitle("Orders")
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                settingsButton
                draftRequestButton
            }
        }
        #endif
    }

    var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Label("Request Settings", systemImage: "gearshape")
        }
        .help("Choose who order requests go to")
    }

    var draftRequestButton: some View {
        Button {
            showingDraft = true
        } label: {
            Label("Draft Request", systemImage: "envelope")
        }
        .disabled(toRequest.isEmpty)
        .help("Write the office one email asking for everything not yet requested")
    }

    // MARK: - Actions

    /// Adds every web link among `urls`, then fetches page titles in the background.
    /// - Returns: false when nothing dropped was a web link, so the drop is refused.
    @discardableResult
    func addLinks(_ urls: [URL]) -> Bool {
        let webLinks = urls.filter(OrderService.isWebURL)
        guard !webLinks.isEmpty else {
            notice = "That isn't a web link."
            return false
        }
        let created = OrderService.addLinks(webLinks, in: viewContext)
        guard !created.isEmpty else {
            notice = webLinks.count == 1 ? "That link is already on the list." : "Those links are already on the list."
            return true
        }
        notice = nil
        saveCoordinator.save(viewContext, reason: "Add order link")
        Task {
            await OrderLinkTitleFetcher.fillMissingTitles(created) {
                saveCoordinator.save(viewContext, reason: "Order link title")
            }
        }
        return true
    }

    func addTypedLink() {
        guard let url = OrderService.webURL(from: linkText) else {
            notice = "That doesn't look like a web link."
            return
        }
        addLinks([url])
        linkText = ""
    }

    func addPasted(_ strings: [String]) {
        let urls = strings
            .flatMap { $0.components(separatedBy: .whitespacesAndNewlines) }
            .compactMap(OrderService.webURL(from:))
        addLinks(urls)
    }

    func setReceived(_ item: CDOrderItem, _ received: Bool) {
        OrderService.setReceived([item], received)
        saveCoordinator.save(viewContext, reason: received ? "Order received" : "Order not received")
    }

    func setQuantity(_ item: CDOrderItem, _ quantity: Int) {
        OrderService.setQuantity(item, to: quantity)
        quantitySave?.cancel()
        quantitySave = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            saveCoordinator.save(viewContext, reason: "Order quantity")
        }
    }

    func flushQuantitySave() {
        guard let pending = quantitySave else { return }
        pending.cancel()
        quantitySave = nil
        saveCoordinator.save(viewContext, reason: "Order quantity")
    }

    func markConfirmed(_ items: [CDOrderItem]) {
        OrderService.markConfirmed(items)
        saveCoordinator.save(viewContext, reason: "Order request confirmed")
    }

    func clearConfirmation(_ items: [CDOrderItem]) {
        OrderService.clearConfirmation(items)
        saveCoordinator.save(viewContext, reason: "Clear order confirmation")
    }

    func markAskedFor(_ items: [CDOrderItem]) {
        OrderService.markRequested(items, from: OrderRequestRecipient.stored().label)
        saveCoordinator.save(viewContext, reason: "Mark order asked for")
    }

    func moveBackToRequest(_ items: [CDOrderItem]) {
        OrderService.moveBackToRequest(items)
        saveCoordinator.save(viewContext, reason: "Move order back to request")
    }

    func delete(_ items: [CDOrderItem]) {
        OrderService.delete(items, in: viewContext)
        saveCoordinator.save(viewContext, reason: "Delete order item")
    }

    func clearReceived() {
        delete(received)
        showingReceived = false
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct OrdersViewPreview: View {
    var body: some View {
        OrdersView()
            .previewEnvironment()
    }
}

#Preview {
    OrdersViewPreview()
}
