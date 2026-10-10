// RestockNeedSheet.swift
// "We need…": type a name or paste a product link (which switches it to Needs
// ordering and reads the page's title), choose where it comes from, how many,
// and whether to keep it stocked from now on (a staple on the shelf).

import SwiftUI
import CoreData

struct RestockNeedSheet: View {
    let author: RestockAuthor
    /// What to start with, for a staple-name chip or a test.
    var initialName = ""

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var link: URL?
    @State private var source = RestockSource.office
    @State private var quantity = 1
    @State private var note = ""
    @State private var keepStocked = false
    @State private var place = ""
    @State private var isFetchingTitle = false
    /// The name the page's title filled in; typing over it keeps the typing.
    @State private var fetchedName: String?
    @State private var notice: String?

    private var canAdd: Bool { !name.trimmed().isEmpty || (link != nil && !keepStocked) }

    private var addLabel: String {
        if keepStocked { return "Add to the Shelf" }
        return source == .office ? "Add to Office Run" : "Add to To Order"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "What is it?", text: $name,
                        prompt: Text(isFetchingTitle ? "Reading the page…" : "Glue sticks")
                    )
                        .onSubmit(takeLinkFromName)
                        .onChange(of: name) { takeLinkFromName() }
                    if let link {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                            Text(Self.caption(for: link))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            if isFetchingTitle {
                                ProgressView().controlSize(.small)
                            }
                            Spacer()
                            Button("Remove Link", systemImage: "xmark.circle.fill") {
                                self.link = nil
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    } else {
                        HStack {
                            Text("Or paste a product link. It fills in the name and switches to Needs ordering.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            PasteButton(payloadType: String.self) { strings in
                                pasted(strings)
                            }
                            .labelStyle(.titleAndIcon)
                            .controlSize(.small)
                        }
                    }
                    if let notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("We need…")
                }

                Section("Where does it come from?") {
                    Picker("Comes from", selection: $source) {
                        Text("From the office").tag(RestockSource.office)
                        Text("Needs ordering").tag(RestockSource.order)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(source == .office ? "Goes on the office run." : "Joins the next request email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Stepper("How many: \(quantity)", value: $quantity, in: OrderService.quantityRange)
                    TextField("Note: brand, size, color (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Toggle(isOn: $keepStocked) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep it stocked")
                            Text("Put it on the shelf, so anyone can mark it low next time.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if keepStocked {
                        TextField("Lives in (Art shelf, Bathrooms…)", text: $place)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("We Need…")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addLabel, action: add)
                        .disabled(!canAdd)
                }
            }
            .onAppear {
                if name.isEmpty { name = initialName }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    // MARK: - Links

    /// "amazon.com/dp/B0B2MMB4LJ": the link without its scheme and "www.".
    static func caption(for url: URL) -> String {
        url.absoluteString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
    }

    /// A link typed or pasted into the name field moves to the link.
    private func takeLinkFromName() {
        let text = name.trimmed()
        guard text.contains("://") || text.lowercased().hasPrefix("www."),
              let url = OrderService.webURL(from: text) else { return }
        name = ""
        use(url)
    }

    private func pasted(_ strings: [String]) {
        // The first web link in what was pasted: share text's other words
        // ("Look at this!") would otherwise read as sites of their own.
        let url = strings.lazy.compactMap(OrderService.firstWebURL(in:)).first
        guard let url else {
            notice = "That isn't a web link."
            return
        }
        use(url)
    }

    private func use(_ url: URL) {
        notice = nil
        let cleaned = URL(string: OrderLinkCleaner.clean(url.absoluteString)) ?? url
        link = cleaned
        source = .order
        guard name.trimmed().isEmpty else { return }
        isFetchingTitle = true
        Task {
            let title = await OrderLinkTitleFetcher.fetchTitle(for: cleaned)
            isFetchingTitle = false
            // The guide may have typed a name, or changed the link, meanwhile.
            guard let title, link == cleaned, name.trimmed().isEmpty || name == fetchedName else { return }
            let short = OrderLinkCleaner.shortTitle(title)
            fetchedName = short
            name = short
        }
    }

    // MARK: - Adding

    private func add() {
        if keepStocked {
            addStaple()
        } else {
            addOneOff()
        }
    }

    private func addOneOff() {
        guard let added = RestockService.addOneOff(
            title: name, link: link, quantity: quantity, source: source, note: note, by: author, in: viewContext
        ) else { return }
        guard added.isNew else {
            notice = "That's already on the list."
            return
        }
        saveCoordinator.save(viewContext, reason: "Add to Restock")
        let need = added.object
        if need.title.trimmed().isEmpty {
            // Added before its page answered: the title follows when it does.
            Task {
                await OrderLinkTitleFetcher.fillMissingTitles([need]) {
                    saveCoordinator.save(viewContext, reason: "Restock link title")
                }
            }
        }
        dismiss()
    }

    /// A staple needed now: on the shelf at Out, with its need's count.
    private func addStaple() {
        let details = RestockService.StapleDetails(name: name, place: place, source: source, link: link, note: note)
        guard let added = RestockService.addStaple(details, level: .out, by: author, in: viewContext) else { return }
        let staple = added.object
        if !added.isNew {
            // Already on the shelf: keep what it had where the sheet was left
            // blank, and take what the guide filled in. A link makes it ordered.
            var merged = RestockService.StapleDetails(staple)
            if !details.place.trimmed().isEmpty { merged.place = details.place }
            if !details.note.trimmed().isEmpty { merged.note = details.note }
            if let link = details.link {
                merged.link = link
                merged.source = .order
            }
            RestockService.updateStaple(staple, to: merged, in: viewContext)
            RestockService.setLevel(staple, to: .out, by: author, in: viewContext)
        }
        for need in RestockService.openNeeds(for: staple, in: viewContext) where need.stage == .toRequest {
            RestockService.setQuantity(need, to: quantity)
        }
        saveCoordinator.save(viewContext, reason: "Add a staple")
        dismiss()
    }
}
