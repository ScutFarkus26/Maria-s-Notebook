// PrepChecklistItemEditorSheet.swift
// Sheet to add new items to a prep checklist.

import SwiftUI
import CoreData

struct PrepChecklistItemEditorSheet: View {
    let checklist: CDPrepChecklist
    @Bindable var viewModel: PrepChecklistViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var category: String = ""
    @State private var existingCategories: [String] = []

    var body: some View {
        Form {
            Section("Item") {
                TextField("Item title", text: $title)
            }

            Section("Category") {
                if !existingCategories.isEmpty {
                    Picker("Category", selection: $category) {
                        Text("None").tag("")
                        ForEach(existingCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                }

                TextField("Or enter new category", text: $category)
            }

            Section {
                Button {
                    addItem()
                } label: {
                    Label("Add Item", systemImage: "plus.circle.fill")
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Existing items preview
            if !checklist.itemsArray.isEmpty {
                Section("Current Items") {
                    ForEach(checklist.itemsArray, id: \.id) { item in
                        HStack {
                            Text(item.title)
                                .font(.subheadline)

                            Spacer()

                            if !item.category.isEmpty {
                                Text(item.category)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.secondary.opacity(UIConstants.OpacityConstants.light))
                                    )
                            }
                        }
                    }
                    .onDelete { offsets in
                        let items = checklist.itemsArray
                        for index in offsets {
                            viewModel.deleteItem(items[index], context: viewContext)
                        }
                    }
                }
            }
        }
        .navigationTitle("Add Items")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            let categories = Set(checklist.itemsArray.map(\.category).filter { !$0.isEmpty })
            existingCategories = categories.sorted()
        }
    }

    private func addItem() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        viewModel.addItem(
            to: checklist,
            title: trimmed,
            category: category,
            context: viewContext
        )

        // Update categories
        if !category.isEmpty && !existingCategories.contains(category) {
            existingCategories.append(category)
            existingCategories.sort()
        }

        title = ""
    }
}
