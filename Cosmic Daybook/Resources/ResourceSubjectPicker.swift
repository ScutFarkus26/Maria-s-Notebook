import SwiftUI

/// Multi-select area picker for linking resources to lesson areas.
/// Shown as a NavigationLink destination inside import/edit sheets.
struct ResourceAreaPicker: View {
    let availableAreas: [String]
    @Binding var selectedAreas: Set<String>

    var body: some View {
        List {
            if availableAreas.isEmpty {
                Text("No areas available yet. Areas come from your lessons.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if !selectedAreas.isEmpty {
                    Section {
                        HStack {
                            Text("\(selectedAreas.count) area\(selectedAreas.count == 1 ? "" : "s") selected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear All") {
                                selectedAreas.removeAll()
                            }
                            .font(.caption)
                        }
                    }
                }

                Section {
                    ForEach(availableAreas, id: \.self) { area in
                        Button {
                            if selectedAreas.contains(area) {
                                selectedAreas.remove(area)
                            } else {
                                selectedAreas.insert(area)
                            }
                        } label: {
                            HStack {
                                Text(area)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedAreas.contains(area) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Link to Areas")
        .inlineNavigationTitle()
    }
}
