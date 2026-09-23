import SwiftUI

// MARK: - Editable Details Section

struct SupplyEditableDetailsSection: View {
    @Binding var editName: String
    @Binding var editCategory: SupplyCategory
    @Binding var editLocation: String
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
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editNotes)
                        .frame(minHeight: 80)
                        .padding(8)
                        .surface(
                            UIConstants.CornerRadius.medium,
                            fill: Color.primary.opacity(UIConstants.OpacityConstants.trace),
                            stroke: Color.primary.opacity(UIConstants.OpacityConstants.subtle),
                            style: .continuous
                        )
                }
            }
            .padding()
            .cardStyle()
        }
    }
}
