import SwiftUI
import SwiftData

// MARK: - Perpetual Calendar View

/// A continuous-scroll calendar in classic landscape spreadsheet layout:
/// month columns side by side, days running vertically, with an editable
/// note field beside each day. Scrolls seamlessly across year boundaries.
/// Non-school days from Settings sync automatically; US federal holidays
/// are pre-populated.
struct PerpetualCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\CalendarNote.year), SortDescriptor(\CalendarNote.month), SortDescriptor(\CalendarNote.day)])
    private var allNotes: [CalendarNote]

    @State private var displayYear: Int = Calendar.current.component(.year, from: Date())
    @State private var editingCell: CellID?
    @State private var editText: String = ""
    @State private var nonSchoolCells: Set<CellID> = []
    @State private var loadedYearRange: ClosedRange<Int>?

    private static let monthNames = Calendar.current.monthSymbols

    /// How many years before/after the current year to render
    private static let yearRadius = 5

    private var yearRange: ClosedRange<Int> {
        let now = Calendar.current.component(.year, from: Date())
        return (now - Self.yearRadius)...(now + Self.yearRadius)
    }

    private var allMonths: [MonthID] {
        yearRange.flatMap { year in
            (1...12).map { MonthID(year: year, month: $0) }
        }
    }

    /// Notes keyed by year+month+day
    private var notesLookup: [CellID: CalendarNote] {
        var lookup: [CellID: CalendarNote] = [:]
        for note in allNotes {
            lookup[CellID(year: note.year, month: note.month, day: note.day)] = note
        }
        return lookup
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Calendar") {
                yearStepper
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    calendarGrid
                        .padding(16)
                }
                .onAppear {
                    scrollToCurrentMonth(proxy)
                }
                .onChange(of: displayYear) { _, newYear in
                    withAnimation {
                        proxy.scrollTo(MonthID(year: newYear, month: 1), anchor: .leading)
                    }
                }
            }
        }
        .task { await loadNonSchoolDays() }
    }

    // MARK: - Year Stepper

    private var yearStepper: some View {
        HStack(spacing: 12) {
            Button {
                displayYear -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(String(displayYear))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 60)

            Button {
                displayYear += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Today") {
                displayYear = AppCalendar.shared.component(.year, from: Date())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func scrollToCurrentMonth(_ proxy: ScrollViewProxy) {
        let cal = AppCalendar.shared
        let now = Date()
        let m = MonthID(
            year: cal.component(.year, from: now),
            month: cal.component(.month, from: now)
        )
        proxy.scrollTo(m, anchor: .leading)
    }

    // MARK: - Non-School Day Loading

    private func loadNonSchoolDays() async {
        let cal = AppCalendar.shared
        let range = yearRange
        var startComps = DateComponents()
        startComps.year = range.lowerBound
        startComps.month = 1
        startComps.day = 1
        let years = range.upperBound - range.lowerBound + 1
        guard let start = cal.date(from: startComps),
              let end = cal.date(byAdding: .year, value: years, to: start) else { return }

        let dates = await SchoolCalendar.nonSchoolDays(in: start..<end, using: modelContext)
        var cells = Set<CellID>()
        for date in dates {
            let y = cal.component(.year, from: date)
            let m = cal.component(.month, from: date)
            let d = cal.component(.day, from: date)
            cells.insert(CellID(year: y, month: m, day: d))
        }
        await MainActor.run {
            nonSchoolCells = cells
            loadedYearRange = range
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        LazyHStack(alignment: .top, spacing: 0) {
            ForEach(allMonths) { monthID in
                monthColumn(monthID)
                    .id(monthID)
                    .onAppear { trackVisibleYear(monthID) }

                Divider()
            }
        }
    }

    /// Update the displayed year label as columns scroll into view
    private func trackVisibleYear(_ monthID: MonthID) {
        if monthID.month >= 1 && monthID.month <= 6 && monthID.year != displayYear {
            // When early months of a new year appear, update the label
            // Use month <= 6 so the label flips roughly when a year is centered
            displayYear = monthID.year
        }
    }

    private func monthColumn(_ monthID: MonthID) -> some View {
        let days = daysInMonth(monthID)
        let isNewYear = monthID.month == 1

        return VStack(spacing: 0) {
            // Show year label above January columns
            VStack(spacing: 0) {
                if isNewYear {
                    Text(String(monthID.year))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }

                Text(Self.monthNames[monthID.month - 1])
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
            }

            Divider()

            ForEach(1...days, id: \.self) { day in
                dayRow(monthID: monthID, day: day)
                if day < days {
                    Divider()
                        .opacity(0.4)
                }
            }
        }
        .frame(width: 180)
    }

    private func daysInMonth(_ monthID: MonthID) -> Int {
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = monthID.year
        comps.month = monthID.month
        comps.day = 1
        guard let date = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    // MARK: - Day Row

    private func dayRow(monthID: MonthID, day: Int) -> some View {
        let cellID = CellID(year: monthID.year, month: monthID.month, day: day)
        let holiday = PerpetualHolidays.holiday(month: monthID.month, day: day, year: monthID.year)
        let note = notesLookup[cellID]
        let displayText = note?.text ?? holiday ?? ""
        let isEditing = editingCell == cellID
        let isHoliday = holiday != nil && (note == nil || note?.text.isEmpty == true)
        let isToday = isTodayCell(cellID)
        let isNoSchool = nonSchoolCells.contains(cellID)

        return HStack(spacing: 0) {
            Text("\(day)")
                .font(.caption.monospacedDigit().weight(isToday ? .bold : .regular))
                .foregroundStyle(dayNumberColor(isToday: isToday, isNoSchool: isNoSchool))
                .frame(width: 28, alignment: .trailing)
                .padding(.trailing, 6)

            if isEditing {
                TextField("Add note…", text: $editText, onCommit: {
                    commitEdit(cellID: cellID)
                })
                .font(.caption)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onSubmit { commitEdit(cellID: cellID) }
            } else {
                Text(displayText)
                    .font(.caption)
                    .foregroundStyle(noteTextColor(isHoliday: isHoliday, isNoSchool: isNoSchool))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginEdit(cellID: cellID, currentText: note?.text ?? holiday ?? "")
                    }
            }

            if isNoSchool && !isEditing {
                Circle()
                    .fill(Color.red.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .help("No School")
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(rowBackground(isToday: isToday, isHoliday: isHoliday, isNoSchool: isNoSchool))
    }

    private func dayNumberColor(isToday: Bool, isNoSchool: Bool) -> Color {
        if isToday { return .accentColor }
        if isNoSchool { return .red }
        return .primary
    }

    private func noteTextColor(isHoliday: Bool, isNoSchool: Bool) -> Color {
        if isNoSchool { return .red }
        if isHoliday { return .blue }
        return .primary
    }

    private func rowBackground(isToday: Bool, isHoliday: Bool, isNoSchool: Bool) -> some View {
        Group {
            if isToday {
                Color.accentColor.opacity(0.08)
            } else if isNoSchool {
                Color.red.opacity(0.06)
            } else if isHoliday {
                Color.blue.opacity(0.04)
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Today Detection

    private func isTodayCell(_ cellID: CellID) -> Bool {
        let now = Date()
        let cal = AppCalendar.shared
        return cal.component(.year, from: now) == cellID.year
            && cal.component(.month, from: now) == cellID.month
            && cal.component(.day, from: now) == cellID.day
    }

    // MARK: - Editing

    private func beginEdit(cellID: CellID, currentText: String) {
        if let previous = editingCell, previous != cellID {
            commitEdit(cellID: previous)
        }
        editText = currentText
        editingCell = cellID
    }

    private func commitEdit(cellID: CellID) {
        let trimmed = editText.trimmed()
        let holiday = PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year)

        if let existing = notesLookup[cellID] {
            if trimmed.isEmpty || trimmed == holiday {
                modelContext.delete(existing)
            } else {
                existing.text = trimmed
                existing.modifiedAt = Date()
            }
        } else if !trimmed.isEmpty && trimmed != holiday {
            let note = CalendarNote(year: cellID.year, month: cellID.month, day: cellID.day, text: trimmed)
            modelContext.insert(note)
        }

        modelContext.safeSave()
        editingCell = nil
        editText = ""
    }
}

// MARK: - Month Identifier

private struct MonthID: Hashable, Identifiable {
    let year: Int
    let month: Int
    var id: Int { year * 12 + month }
}

// MARK: - Cell Identifier

private struct CellID: Hashable {
    let year: Int
    let month: Int
    let day: Int
}

// MARK: - US Federal Holidays

/// Fixed-date and floating US federal holidays.
enum PerpetualHolidays {
    static func holiday(month: Int, day: Int, year: Int) -> String? {
        switch (month, day) {
        case (1, 1):   return "New Year's Day"
        case (6, 19):  return "Juneteenth"
        case (7, 4):   return "Independence Day"
        case (11, 11): return "Veterans Day"
        case (12, 25): return "Christmas Day"
        default: break
        }

        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = cal.date(from: comps) else { return nil }
        let weekday = cal.component(.weekday, from: date)
        let weekOfMonth = (day - 1) / 7 + 1

        switch (month, weekday, weekOfMonth) {
        case (1, 2, 3):  return "MLK Day"
        case (2, 2, 3):  return "Presidents' Day"
        case (5, 2, _) where isLastOccurrence(day: day, month: month, year: year):
            return "Memorial Day"
        case (9, 2, 1):  return "Labor Day"
        case (10, 2, 2): return "Columbus Day"
        case (11, 5, 4): return "Thanksgiving"
        default: return nil
        }
    }

    private static func isLastOccurrence(day: Int, month: Int, year: Int) -> Bool {
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = cal.date(from: comps),
              let nextWeek = cal.date(byAdding: .day, value: 7, to: date) else { return false }
        return cal.component(.month, from: nextWeek) != month
    }
}

#Preview {
    PerpetualCalendarView()
        .previewEnvironment()
}
