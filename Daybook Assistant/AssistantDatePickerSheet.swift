import SwiftUI

/// Picks any day, past or future. Days off can be chosen too; the screen then
/// says there's no school.
struct AssistantDatePickerSheet: View {
    let onPick: (Date) -> Void
    @State private var selection: Date
    @Environment(\.dismiss) private var dismiss

    init(date: Date, onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        _selection = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            DatePicker("Day", selection: $selection, displayedComponents: .date)
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
}
