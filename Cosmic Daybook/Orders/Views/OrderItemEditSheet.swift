// OrderItemEditSheet.swift
// Edit one need on Restock: its name, link, quantity and note.

import SwiftUI
import CoreData

struct OrderItemEditSheet: View {
    @ObservedObject var item: CDOrderItem

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var link = ""
    @State private var quantity = 1
    @State private var notes = ""
    @State private var isFetchingTitle = false
    @State private var confirmingDelete = false

    /// The web link in the field: pasted share text keeps only its link.
    private var fetchURL: URL? { OrderService.firstWebURL(in: link) }

    /// Text in the Link field with no web link in it.
    private var linkIsInvalid: Bool { !link.trimmed().isEmpty && fetchURL == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title, prompt: Text(item.host ?? "What it is"))
                    HStack {
                        TextField("Link", text: $link)
                            .autocorrectionDisabled(true)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                        if let url = fetchURL {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("Open the link")
                        }
                    }
                    if linkIsInvalid {
                        Text("That doesn't look like a web link.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        fetchTitle()
                    } label: {
                        if isFetchingTitle {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Reading the page…")
                            }
                        } else {
                            Label("Use the Page's Title", systemImage: "text.badge.checkmark")
                        }
                    }
                    .disabled(fetchURL == nil || isFetchingTitle)
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    TextField("Note for the office (size, color…)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Status") {
                    LabeledContent("Stage", value: item.stage.displayName)
                    if let date = item.requestedAt {
                        LabeledContent("Asked for", value: dateLine(date, detail: item.requestedFrom))
                    }
                    if let date = item.confirmedAt {
                        LabeledContent("Confirmed", value: dateLine(date))
                    }
                    if let date = item.receivedAt {
                        LabeledContent("Received", value: dateLine(date))
                    }
                }

                Section {
                    Button("Delete Item", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(linkIsInvalid)
                }
            }
            .confirmationDialog(
                "Delete this item?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    private func dateLine(_ date: Date, detail: String = "") -> String {
        let day = DateFormatters.mediumDate.string(from: date)
        return detail.isEmpty ? day : "\(day) · \(detail)"
    }

    private func load() {
        title = item.title
        link = item.urlString
        quantity = max(1, Int(item.quantity))
        notes = item.notes
    }

    private func fetchTitle() {
        guard let url = fetchURL else { return }
        isFetchingTitle = true
        Task {
            if let fetched = await OrderLinkTitleFetcher.fetchTitle(for: url) {
                title = fetched
            }
            isFetchingTitle = false
        }
    }

    private func save() {
        OrderService.update(item, title: title, urlString: link, quantity: quantity, notes: notes)
        saveCoordinator.save(viewContext, reason: "Edit a need")
        dismiss()
    }

    private func delete() {
        // Through RestockService: a staple whose need goes is Stocked again.
        RestockService.removeNeeds([item], by: RestockAuthor.current(in: viewContext), in: viewContext)
        saveCoordinator.save(viewContext, reason: "Remove a need")
        dismiss()
    }
}
