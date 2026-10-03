// StapleEditSheet.swift
// A staple's name, place, source, link and note: Add a Staple, and Edit… from
// a tile's menu. Changes go through RestockService; a need not yet asked for
// follows the staple's new name, link and source.

import SwiftUI
import CoreData

struct StapleEditSheet: View {
    let target: StapleSheetTarget
    let author: RestockAuthor

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var place = ""
    @State private var source = RestockSource.office
    @State private var linkText = ""
    @State private var note = ""
    @State private var notice: String?

    private var isAdding: Bool {
        if case .add = target { return true }
        return false
    }

    /// A typed link that isn't a web address.
    private var linkIsInvalid: Bool {
        !linkText.trimmed().isEmpty && OrderService.webURL(from: linkText) == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Paper towels"))
                    TextField("Place", text: $place, prompt: Text("Where it lives: Bathrooms, Art shelf…"))
                }
                Section("Where it comes from") {
                    Picker("Comes from", selection: $source) {
                        Text("From the office").tag(RestockSource.office)
                        Text("Needs ordering").tag(RestockSource.order)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    TextField("Product link (optional)", text: $linkText)
                        .autocorrectionDisabled(true)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    if linkIsInvalid {
                        Text("That doesn't look like a web link.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Note: brand, size, color (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isAdding ? "Add a Staple" : "Edit Staple")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Add" : "Save", action: save)
                        .disabled(name.trimmed().isEmpty || linkIsInvalid)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    private var details: RestockService.StapleDetails {
        RestockService.StapleDetails(
            name: name,
            place: place,
            source: source,
            link: OrderService.webURL(from: linkText),
            note: note
        )
    }

    private func load() {
        switch target {
        case .add(let preset):
            if name.isEmpty { name = preset }
        case .edit(let supply):
            let current = RestockService.StapleDetails(supply)
            name = current.name
            place = current.place
            source = current.source
            linkText = current.link?.absoluteString ?? ""
            note = current.note
        }
    }

    private func save() {
        switch target {
        case .add:
            guard let added = RestockService.addStaple(details, by: author, in: viewContext) else { return }
            guard added.isNew else {
                notice = "\(added.object.name) is already on the shelf."
                return
            }
            saveCoordinator.save(viewContext, reason: "Add a staple")
        case .edit(let supply):
            if RestockService.updateStaple(supply, to: details, in: viewContext) {
                saveCoordinator.save(viewContext, reason: "Edit a staple")
            }
        }
        dismiss()
    }
}
