// ResourceLibraryView+Sheets.swift
// Bulk category picker, bulk tag picker, and per-resource category picker sheets.

import SwiftUI

extension ResourceLibraryView {

    // MARK: - Bulk Category Sheet

    var bulkCategorySheet: some View {
        NavigationStack {
            List {
                ForEach(ResourceCategory.allCases) { category in
                    Button {
                        bulkSetCategory(category)
                        showingBulkCategoryPicker = false
                    } label: {
                        Label(category.rawValue, systemImage: category.icon)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Set Category")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingBulkCategoryPicker = false
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #endif
    }

    // MARK: - Bulk Tag Sheet

    var bulkTagSheet: some View {
        NavigationStack {
            Form {
                let noun = selectedResourceIDs.count == 1 ? "Resource" : "Resources"
                Section("Add Tags to \(selectedResourceIDs.count) \(noun)") {
                    TagPicker(selectedTags: $bulkTags)
                }
            }
            .navigationTitle("Add Tags")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingBulkTagPicker = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        bulkAddTags(bulkTags)
                        showingBulkTagPicker = false
                    }
                    .disabled(bulkTags.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    // MARK: - Per-Resource Category Picker

    func categoryPickerSheet(for resource: Resource) -> some View {
        NavigationStack {
            List {
                ForEach(ResourceCategory.allCases) { category in
                    Button {
                        resource.category = category
                        resource.modifiedAt = Date()
                        modelContext.safeSave()
                        resourceToRecategorize = nil
                    } label: {
                        HStack {
                            Label(category.rawValue, systemImage: category.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            if resource.category == category {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Change Category")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resourceToRecategorize = nil
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #endif
    }
}
