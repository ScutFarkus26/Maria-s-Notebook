// CalendarDayCell.swift
// The day row both calendar grids draw: parsha label, day number, note text.

import SwiftUI

// MARK: - Metrics

/// The spacing a grid gives its day cells. The two grids differ only in these
/// numbers, so they are values rather than two copies of the same layout.
struct CalendarDayMetrics {
    /// Spacing between the rows stacked inside one day cell.
    var rowSpacing: CGFloat
    /// Inset applied to every row of the cell.
    var horizontalPadding: CGFloat
    /// Gap above the parsha label, when one is shown.
    var parshaTopPadding: CGFloat
    /// Padding around the day-number row itself.
    var dayRowVerticalPadding: CGFloat
    /// Padding around the whole cell.
    var cellVerticalPadding: CGFloat

    /// The planning calendar's tighter cells, which also carry event and todo rows.
    static let planning = CalendarDayMetrics(
        rowSpacing: 1,
        horizontalPadding: 8,
        parshaTopPadding: 1,
        dayRowVerticalPadding: 0,
        cellVerticalPadding: 1
    )
}

// MARK: - Day cell

/// One day of a calendar grid: an optional parsha label, the day number, and
/// either the day's note text or the text field editing it.
///
/// `extra` is where a grid adds its own rows under the day number — the
/// planning calendar's Mac events and todo deadlines — so that everything
/// still shares one stack and one set of paddings.
struct CalendarDayCell<Extra: View>: View {
    let cellID: CellID
    let isToday: Bool
    let isNonSchool: Bool
    let parsha: String?
    let displayText: String
    let isHoliday: Bool
    let isEditing: Bool
    @Binding var editText: String
    let metrics: CalendarDayMetrics
    let onBeginEdit: () -> Void
    let onCommit: () -> Void
    @ViewBuilder let extra: () -> Extra

    init(
        cellID: CellID,
        isToday: Bool,
        isNonSchool: Bool,
        parsha: String?,
        displayText: String,
        isHoliday: Bool,
        isEditing: Bool,
        editText: Binding<String>,
        metrics: CalendarDayMetrics,
        onBeginEdit: @escaping () -> Void,
        onCommit: @escaping () -> Void,
        @ViewBuilder extra: @escaping () -> Extra
    ) {
        self.cellID = cellID
        self.isToday = isToday
        self.isNonSchool = isNonSchool
        self.parsha = parsha
        self.displayText = displayText
        self.isHoliday = isHoliday
        self.isEditing = isEditing
        _editText = editText
        self.metrics = metrics
        self.onBeginEdit = onBeginEdit
        self.onCommit = onCommit
        self.extra = extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            if let parsha {
                Text(parsha)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.red.opacity(UIConstants.OpacityConstants.half))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, metrics.parshaTopPadding)
            }

            HStack(spacing: 4) {
                dayNumber

                if isEditing {
                    TextField("", text: $editText)
                        .font(.system(.caption, design: .rounded))
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onSubmit(onCommit)
                } else {
                    Text(displayText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CalendarDayText.noteStyle(isHoliday: isHoliday, isNonSchool: isNonSchool))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onBeginEdit)
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.dayRowVerticalPadding)

            extra()
        }
        .padding(.vertical, metrics.cellVerticalPadding)
    }

    private var dayNumber: some View {
        Text("\(cellID.day)")
            .font(.system(.caption, design: .rounded).monospacedDigit())
            .foregroundStyle(
                isToday
                    ? Color.white
                    : (isNonSchool ? Color.red.opacity(UIConstants.OpacityConstants.half) : Color.secondary)
            )
            .frame(width: 22, height: 22)
            .background {
                if isToday {
                    Circle().fill(Color.accentColor)
                }
            }
    }
}

// MARK: - Shared day text

/// The text decisions both grids make about a day cell.
enum CalendarDayText {

    /// The parsha label for a Saturday cell, or `nil` on any other day.
    static func parsha(for cellID: CellID) -> String? {
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = cellID.year
        comps.month = cellID.month
        comps.day = cellID.day
        guard let date = cal.date(from: comps),
              cal.component(.weekday, from: date) == 7,
              let key = HebrewParshaService.currentParshaKey(on: date) else {
            return nil
        }
        return HebrewParshaService.displayName(forKey: key)
    }

    /// How a day's note reads: red on a non-school day, grey for a holiday
    /// name the user has not overwritten, otherwise the normal text colour.
    static func noteStyle(isHoliday: Bool, isNonSchool: Bool) -> some ShapeStyle {
        if isNonSchool { return AnyShapeStyle(.red.opacity(UIConstants.OpacityConstants.half)) }
        if isHoliday { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }
}
