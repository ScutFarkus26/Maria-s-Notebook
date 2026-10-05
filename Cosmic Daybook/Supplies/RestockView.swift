// RestockView.swift
// Restock: what the classroom needs, and the shelf it comes from. The needs
// are an office run (to fetch on the next walk to the office) and a to-order
// list (one request email to the office); the shelf is the staples, grouped
// by where they live, marked Stocked, Low or Out with a click. A staple that
// goes Low or Out joins a list; checking it off puts it back to Stocked.
// Every change goes through RestockService. Sections are in +Needs and
// +Shelf, the changes in +Actions.

import SwiftUI
import CoreData

struct RestockView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(SaveCoordinator.self) var saveCoordinator
    @Environment(\.dependencies) var dependencies
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.appRouter) var appRouter
    #else
    @Environment(\.openSettings) var openSettings
    #endif

    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDSupply.name, ascending: true)
    ]) var suppliesRaw: FetchedResults<CDSupply>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDOrderItem.createdAt, ascending: true)
    ]) var itemsRaw: FetchedResults<CDOrderItem>

    @SyncedAppStorage(OrderRequestPrefs.recipientEmailKey) var recipientEmail: String = ""

    /// Who this device's changes are stamped with, and who reads as "You".
    @State var viewer: RestockAuthor?
    /// The names people set for themselves (`ClassroomNames`), so an
    /// assistant's current name shows on her changes, old ones included.
    @State var names = ClassroomNames.Snapshot()
    @State var showingNeedSheet = false
    @State var stapleSheet: StapleSheetTarget?
    @State var historyStaple: CDSupply?
    @State var noteStaple: CDSupply?
    @State var noteText = ""
    @State var deletingStaple: CDSupply?
    @State var editingNeed: CDOrderItem?
    @State var showingDraft = false
    @State var showingSettings = false
    @State var showingAskedFor = false
    @State var showingReceived = false
    @State var confirmingClearReceived = false
    /// Restock records the lead guide's assistant can't see yet (`+ShareBanner`).
    @State var shareGap: RestockShareGap?
    /// The pending save for a burst of taps (levels, −/+), so marking three
    /// staples is one save and one CloudKit push, not three.
    @State var pendingSave: Task<Void, Never>?

    // MARK: - What the page reads

    /// One per staple: a staple cloned between the stores can come back twice
    /// until the launch-time cleanup folds the copies away.
    var staples: [CDSupply] { Array(suppliesRaw).uniqueByID }

    var items: [CDOrderItem] { Array(itemsRaw) }

    var openNeeds: [CDOrderItem] { items.filter { $0.receivedAt == nil } }

    var officeRun: [CDOrderItem] { openNeeds.filter { $0.source == .office } }

    /// Needs to order that the office hasn't been asked for yet.
    var toRequest: [CDOrderItem] {
        openNeeds.filter { $0.source == .order && $0.stage == .toRequest }
    }

    var askedFor: [OrderRequestGroup] { OrderService.openRequests(items) }

    var confirmed: [CDOrderItem] {
        items.filter { $0.stage == .confirmed }
            .sorted { ($0.confirmedAt ?? .distantPast) < ($1.confirmedAt ?? .distantPast) }
    }

    var received: [CDOrderItem] {
        items.filter { $0.stage == .received }
            .sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) }
    }

    var staplesByID: [String: CDSupply] {
        var byID: [String: CDSupply] = [:]
        for staple in staples {
            if let id = staple.id?.uuidString.uppercased() { byID[id] = staple }
        }
        return byID
    }

    var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var author: RestockAuthor { (viewer ?? RestockAuthor(role: .leadGuide)).reading(names) }

    // MARK: - Body

    var body: some View {
        let byID = staplesByID
        let digest = RestockDigest.make(needs: openNeeds, levels: RestockDigest.levels(of: staples))
        VStack(spacing: 0) {
            #if os(iOS)
            ViewHeader(title: "Restock") {
                HStack(spacing: 10) {
                    settingsButton
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                    weNeedButton
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
            Divider()
            #endif

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    shareBanner
                    needsSection(digest: digest, staplesByID: byID)
                    shelfSection
                }
                .padding(.horizontal, isCompact ? 16 : 24)
                .padding(.vertical, 16)
            }
        }
        .sheet(isPresented: $showingNeedSheet) {
            RestockNeedSheet(author: author)
        }
        .sheet(item: $stapleSheet) { target in
            StapleEditSheet(target: target, author: author)
        }
        .sheet(item: $historyStaple) { staple in
            StapleHistorySheet(supply: staple, viewer: author)
        }
        .sheet(item: $editingNeed) { need in
            OrderItemEditSheet(item: need)
        }
        .sheet(isPresented: $showingDraft) {
            OrderRequestDraftSheet(items: toRequest)
        }
        .sheet(isPresented: $showingSettings) {
            OrderRequestSettingsSheet()
        }
        .alert(
            noteStaple.map { "Note for \($0.name)" } ?? "Note",
            isPresented: Binding(get: { noteStaple != nil }, set: { if !$0 { noteStaple = nil } })
        ) {
            TextField("Brand, size, where it's kept", text: $noteText)
            Button("Save") { saveNote() }
            Button("Cancel", role: .cancel) { noteStaple = nil }
        }
        .confirmationDialog(
            deletingStaple.map { "Delete \($0.name)?" } ?? "Delete?",
            isPresented: Binding(get: { deletingStaple != nil }, set: { if !$0 { deletingStaple = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteStaple() }
            Button("Cancel", role: .cancel) { deletingStaple = nil }
        } message: {
            Text("It comes off the shelf and its history goes with it, on every device.")
        }
        .confirmationDialog(
            "Remove \(received.count) checked-off \(received.count == 1 ? "item" : "items")?",
            isPresented: $confirmingClearReceived,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { clearReceived() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They are deleted from Restock on all your devices.")
        }
        .task {
            if viewer == nil { viewer = RestockAuthor.current(in: viewContext) }
            names = ClassroomNames.snapshot(in: viewContext)
            reconcile()
            await refreshShareGap()
        }
        // Two devices can each open a need for one staple before either
        // syncs; the page keeps one whenever needs change, here or elsewhere.
        .onPresentationDataChangeWhenVisible(of: ["OrderItem"], in: viewContext, catchUpOnAppear: false) {
            reconcile()
        }
        // Someone renamed themselves: redraw the who-lines with the new name.
        .onPresentationDataChangeWhenVisible(of: ["ClassroomPerson"], in: viewContext, catchUpOnAppear: false) {
            names = ClassroomNames.snapshot(in: viewContext)
        }
        .onDisappear(perform: flushPendingSave)
        .navigationTitle("Restock")
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                settingsButton
                weNeedButton
            }
        }
        #endif
    }

    var weNeedButton: some View {
        Button {
            showingNeedSheet = true
        } label: {
            Label("We need…", systemImage: "plus")
        }
        .help("Add something to the office run or the to-order list")
    }

    var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Label("Request Settings", systemImage: "gearshape")
        }
        .help("Choose who order requests go to")
    }
}

/// What the staple sheet edits: a new staple (perhaps named already) or one
/// on the shelf.
enum StapleSheetTarget: Identifiable {
    case add(name: String)
    case edit(CDSupply)

    var id: String {
        switch self {
        case .add(let name): "add:\(name)"
        case .edit(let supply): supply.objectID.uriRepresentation().absoluteString
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct RestockViewPreview: View {
    var body: some View {
        RestockView()
            .previewEnvironment()
    }
}

#Preview {
    RestockViewPreview()
}
