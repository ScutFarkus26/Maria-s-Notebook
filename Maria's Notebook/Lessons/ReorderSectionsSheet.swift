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

    /// The bands this sequence actually has, named the way the map and the Checklist
    /// name them — the sheet would otherwise offer "Chains" and "chains" as two rows
    /// and save an order neither grid could match.
    private var existing: [String] {
        let trimmedArea = area.trimmed()
        let trimmedSequence = sequence.trimmed()
        // Trimmed on both sides: a lesson filed under "Fractions " was dropping out
        // of this list, and saving then wrote an order that didn't mention its
        // section — which sent that section to the end of both grids.
        let filtered: [CDLesson] = lessons.filter {
            $0.area.trimmed().caseInsensitiveCompare(trimmedArea) == .orderedSame
                && $0.sequence.trimmed().caseInsensitiveCompare(trimmedSequence) == .orderedSame
        }
        return LessonSectionGrouping.sectionNames(in: filtered)
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
