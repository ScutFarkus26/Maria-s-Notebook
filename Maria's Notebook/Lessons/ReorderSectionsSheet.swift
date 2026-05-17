// Maria's Notebook/Lessons/ReorderSectionsSheet.swift
// NEW FILE — add this file to the Lessons folder.

import SwiftUI
import CoreData

struct ReorderSectionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let area: String
    let sequence: String
    let lessons: [CDLesson]

    @State private var items: [String] = []
    @State private var isEditing: Bool = false

    private var existing: [String] {
        let filtered: [CDLesson] = lessons.filter {
            $0.area.caseInsensitiveCompare(area) == .orderedSame
                && $0.sequence.caseInsensitiveCompare(sequence) == .orderedSame
        }
        let sections: [String] = filtered.map { $0.section.trimmed() }
        let unique: Set<String> = Set(sections.filter { !$0.isEmpty })
        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items, id: \.self) { s in
                    Text(s)
                }
                .onMove { from, to in
                    items.move(fromOffsets: from, toOffset: to)
                }
#if os(macOS)
                .moveDisabled(!isEditing)
#endif
            }
            .navigationTitle("Reorder Sections")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        FilterOrderStore.saveSectionOrder(items, for: area, sequence: sequence)
                        FilterOrderStore.resetCache()
                        dismiss()
                    }
                }
#if os(iOS)
                ToolbarItem(placement: .automatic) {
                    EditButton()
                }
#endif
#if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Toggle("Reorder", isOn: $isEditing)
                        .toggleStyle(.button)
                }
#endif
            }
            .task {
                items = FilterOrderStore.loadSectionOrder(for: area, sequence: sequence, existing: existing)
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}
