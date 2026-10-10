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
                            date = Self.defaultDate(on: Date(), hour: defaultHour, calendar: calendar)
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
                        get: { date ?? DateCalculations.startOfDay(Date(), calendar: calendar) },
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

    /// The date the toggle turns on to: `day` at `hour` o'clock, or the start
    /// of `day` with no hour. The hour is set on the clock, not added to
    /// midnight, so 9 stays 9 AM on the Sundays the clocks change (adding nine
    /// hours lands at 8 or 10 then).
    nonisolated static func defaultDate(on day: Date, hour: Int?, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        guard let hour else { return start }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start)
            ?? calendar.date(byAdding: .hour, value: hour, to: start)
            ?? start
    }
}
