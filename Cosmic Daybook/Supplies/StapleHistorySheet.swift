// StapleHistorySheet.swift
// A staple's history, newest first: "Low · Ana", "Out", "Restocked", with
// when. Read once when the sheet opens, not from the tile's menu (a menu's
// closure runs on every pass of the tile).

import SwiftUI
import CoreData

struct StapleHistorySheet: View {
    @ObservedObject var supply: CDSupply
    let viewer: RestockAuthor

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [CDSupplyTransaction] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Now", value: supply.level.displayName)
                    if let when = supply.levelChangedAt {
                        let who = viewer.reads(changedByID: supply.levelChangedByID, name: supply.levelChangedByName)
                        LabeledContent("Set by", value: "\(who), \(DateFormatters.mediumDateTime.string(from: when))")
                    }
                }
                Section("History") {
                    if entries.isEmpty {
                        Text("Nothing yet. Each change of level is kept here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries, id: \.objectID) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(Self.line(for: entry))
                            Spacer()
                            if let date = entry.date {
                                Text(DateFormatters.mediumDateTime.string(from: date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(supply.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                entries = RestockService.history(for: supply, in: viewContext)
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    /// The entry's reason; a counted change without one reads as its count.
    static func line(for entry: CDSupplyTransaction) -> String {
        let reason = entry.reason.trimmed()
        if !reason.isEmpty { return reason }
        let change = entry.quantityChange
        return change > 0 ? "Added \(change)" : change < 0 ? "Used \(-change)" : "Changed"
    }
}
