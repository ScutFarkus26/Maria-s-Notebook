import SwiftUI
import CoreData

/// Sheet for adding a new supply
struct AddSupplySheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var category: SupplyCategory = .other
    @State private var location: String = ""
    @State private var currentQuantity: Int = 0
    @State private var notes: String = ""

    private var isValid: Bool {
        !name.trimmed().isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("New Supply")
                        .font(AppTheme.ScaledFont.titleXLarge)

                    // Basic Info Section
                    basicInfoSection

                    Divider()

                    // Stock Info Section
                    stockInfoSection

                    Divider()

                    // Notes Section
                    notesSection
                }
                .padding(24)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add Supply") { addSupply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(16)
            .background(.bar)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 500, minHeight: 550)
        #endif
    }

    // MARK: - Basic Info Section

    @ViewBuilder
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Information")
                .font(.headline)

            TextField("Supply Name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Category picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                categoryPicker
            }

            TextField("Location (optional)", text: $location)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SupplyCategory.allCases) { cat in
                    Button {
                        category = cat
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.caption)
                            Text(cat.rawValue)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(category == cat ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent) : Color.primary.opacity(UIConstants.OpacityConstants.hint))
                        .foregroundStyle(category == cat ? Color.accentColor : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Stock Info Section

    @ViewBuilder
    private var stockInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stock Information")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Current Quantity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("0", value: $currentQuantity, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Stepper("", value: $currentQuantity, in: 0...9999)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - Notes Section

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)

            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                )

            Text("Add any notes about this supply (e.g., preferred brand, supplier).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func addSupply() {
        _ = SupplyService.createSupply(
            name: name.trimmed(),
            category: category,
            location: location.trimmed(),
            currentQuantity: currentQuantity,
            notes: notes.trimmed(),
            in: viewContext
        )
        dismiss()
    }
}

#Preview {
    AddSupplySheet()
        .previewEnvironment()
}
