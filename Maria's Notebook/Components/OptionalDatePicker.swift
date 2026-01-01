import SwiftUI

// NOTE: Moved from GiveLessonComponents.swift for reuse across the app

public struct OptionalDatePicker: View {
    let toggleLabel: String
    let dateLabel: String
    @Binding var date: Date?
    let displayedComponents: DatePickerComponents
    let defaultHour: Int?
    @Environment(\.calendar) private var calendar

    public init(
        toggleLabel: String,
        dateLabel: String,
        date: Binding<Date?>,
        displayedComponents: DatePickerComponents = [.date],
        defaultHour: Int? = nil
    ) {
        self.toggleLabel = toggleLabel
        self.dateLabel = dateLabel
        self._date = date
        self.displayedComponents = displayedComponents
        self.defaultHour = defaultHour
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(toggleLabel, isOn: Binding(
                get: { date != nil },
                set: { newValue in
                    if newValue {
                        if date == nil {
                            if let hour = defaultHour {
                                let base = calendar.startOfDay(for: Date())
                                date = calendar.date(byAdding: .hour, value: hour, to: base) ?? base
                            } else {
                                date = calendar.startOfDay(for: Date())
                            }
                        }
                    } else {
                        date = nil
                    }
                }
            ))
            if date != nil {
                DatePicker(
                    dateLabel,
                    selection: Binding(
                        get: { date ?? Date() },
                        set: { date = $0 }
                    ),
                    displayedComponents: displayedComponents
                )
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.compact)
                #endif
            }
        }
    }
}
