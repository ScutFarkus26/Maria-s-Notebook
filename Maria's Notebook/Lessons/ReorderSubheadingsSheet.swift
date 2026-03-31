// Maria's Notebook/Lessons/ReorderSubheadingsSheet.swift
// NEW FILE — add this file to the Lessons folder.

import SwiftUI
import CoreData

struct ReorderSubheadingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let subject: String
    let group: String
    let lessons: [CDLesson]

    @State private var items: [String] = []
    @State private var isEditing: Bool = false

    private var existing: [String] {
        Array(Set(
            lessons
                .filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
                .filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }
                .map { $0.subheading.trimmed() }
                .filter { !$0.isEmpty }
        ))
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
            .navigationTitle("Reorder Subheadings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        FilterOrderStore.saveSubheadingOrder(items, for: subject, group: group)
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
                items = FilterOrderStore.loadSubheadingOrder(for: subject, group: group, existing: existing)
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}
