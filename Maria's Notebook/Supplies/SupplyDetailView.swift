import SwiftUI
import CoreData

// Detail view for viewing and editing a supply
struct SupplyDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var supply: CDSupply

    @State private var isEditing = false
    @State private var editName: String = ""
    @State private var editCategory: SupplyCategory = .other
    @State private var editLocation: String = ""
    @State private var editNotes: String = ""
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Status header
                    statusHeader

                    // Current stock card
                    currentStockCard

                    // Details section
                    if isEditing {
                        SupplyEditableDetailsSection(
                            editName: $editName,
                            editCategory: $editCategory,
                            editLocation: $editLocation,
                            editNotes: $editNotes
                        )
                    } else {
                        detailsSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle(isEditing ? "Edit Supply" : supply.name)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                        }
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Save") {
                            saveChanges()
                            isEditing = false
                        }
                    } else {
                        Menu {
                            Button {
                                startEditing()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete Supply",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    SupplyService.deleteSupply(supply, in: viewContext)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete \"\(supply.name)\"? This action cannot be undone.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    // MARK: - Actions

    private func startEditing() {
        editName = supply.name
        editCategory = supply.category
        editLocation = supply.location
        editNotes = supply.notes
        isEditing = true
    }

    private func saveChanges() {
        supply.name = editName
        supply.category = editCategory
        supply.location = editLocation
        supply.notes = editNotes
        supply.modifiedAt = Date()
        viewContext.safeSave()
    }

}

// MARK: - Sections

private extension SupplyDetailView {

    var statusHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                    .frame(width: 60, height: 60)

                Image(systemName: supply.category.icon)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(supply.category.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !supply.location.isEmpty {
                    Label(supply.location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
        )
    }

    var currentStockCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Stock")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 24) {
                Text("\(supply.currentQuantity)")
                    .font(AppTheme.ScaledFont.titleXLarge)

                Spacer()
            }
        }
        .padding()
        .cardStyle()
    }

    var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)

            VStack(spacing: 12) {
                detailRow(label: "Name", value: supply.name)
                detailRow(label: "Category", value: supply.category.rawValue)
                detailRow(label: "Location", value: supply.location.isEmpty ? "Not set" : supply.location)

                if !supply.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(supply.notes)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }
            .padding()
            .cardStyle()
        }
    }

    func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext
    let supply = CDSupply(context: ctx)
    supply.name = "Crayons (24-pack)"
    supply.category = .art
    supply.location = "Cabinet A"
    supply.currentQuantity = 12
    supply.notes = "Preferred brand: Crayola. Order from Amazon."

    return SupplyDetailView(supply: supply)
        .previewEnvironment(using: stack)
}
