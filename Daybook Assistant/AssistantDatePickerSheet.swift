import SwiftUI

/// Picks any day of this school year, or ahead. Days off can be chosen too; the screen
/// then says there's no school. Nothing before `earliest`, the share's first day with
/// attendance: the guide shares this school year only.
struct AssistantDatePickerSheet: View {
    let onPick: (Date) -> Void
    let earliest: Date?
    @State private var selection: Date
    @Environment(\.dismiss) private var dismiss

    init(date: Date, earliest: Date?, onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        self.earliest = earliest
        _selection = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            picker
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Choose a Day")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Show") {
                            onPick(selection)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var picker: some View {
        if let earliest {
            DatePicker("Day", selection: $selection, in: earliest..., displayedComponents: .date)
        } else {
            DatePicker("Day", selection: $selection, displayedComponents: .date)
        }
    }
}
