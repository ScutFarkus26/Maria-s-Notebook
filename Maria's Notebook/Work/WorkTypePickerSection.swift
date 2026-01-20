import SwiftUI

struct WorkTypePickerSection: View {
    @Binding var workKind: WorkKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "square.grid.2x2", title: "Work Type")
            Picker("", selection: $workKind) {
                ForEach(WorkKind.allCases) { kind in
                    Label(kind.shortLabel, systemImage: kind.iconName)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Legacy support for callers using WorkModel.WorkType
struct LegacyWorkTypePickerSection: View {
    @Binding var workType: WorkModel.WorkType

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "square.grid.2x2", title: "Work Type")
            Picker("", selection: $workType) {
                ForEach(WorkModel.WorkType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
