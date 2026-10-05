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
            // Scrolls only when the calendar is taller than the sheet, as
            // with large text.
            ScrollView {
                picker
                    .datePickerStyle(.graphical)
                    .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
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
        .presentationDetents([.custom(CalendarDetent.self), .large])
    }

    /// Opens tall enough for the whole month: half the screen on a tall
    /// phone, nearly all of an SE's (whose half cut the calendar off).
    nonisolated struct CalendarDetent: CustomPresentationDetent {
        /// The navigation bar, the graphical calendar and its padding.
        static let calendarHeight: CGFloat = 470

        static func height(in context: Context) -> CGFloat? {
            min(max(context.maxDetentValue / 2, calendarHeight), context.maxDetentValue)
        }
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
