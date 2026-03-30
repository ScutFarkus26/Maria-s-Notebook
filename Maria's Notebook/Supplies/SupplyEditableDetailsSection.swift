import SwiftUI

// MARK: - Editable Details Section

struct SupplyEditableDetailsSection: View {
    @Binding var editName: String
    @Binding var editCategory: SupplyCategory
    @Binding var editLocation: String
    @Binding var editUnit: String
    @Binding var editMinimumThreshold: Int
    @Binding var editReorderAmount: Int
    @Binding var editNotes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Supply name", text: $editName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Category")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Category", selection: $editCategory) {
                        ForEach(SupplyCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Storage location", text: $editLocation)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Unit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("e.g., boxes, packs, items", text: $editUnit)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Minimum Threshold")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("0", value: $editMinimumThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reorder Amount")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("0", value: $editReorderAmount, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editNotes)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                        )
                }
            }
            .padding()
            .cardStyle()
        }
    }
}
