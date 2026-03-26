import SwiftUI
import SwiftData

// MARK: - Perpetual Calendar View

/// A year-at-a-glance calendar in the classic landscape spreadsheet layout:
/// 12 month columns side by side, days running vertically, with an editable
/// note field beside each day. Supports multiple years with a year stepper.
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

    private static let monthNames = Calendar.current.monthSymbols

    /// Notes for the currently displayed year, keyed by month+day
    private var notesLookup: [CellID: CalendarNote] {
        var lookup: [CellID: CalendarNote] = [:]
        for note in allNotes where note.year == displayYear {
            lookup[CellID(month: note.month, day: note.day)] = note
        }
        return lookup
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Calendar") {
                yearStepper
            }

            Divider()

            ScrollView([.horizontal, .vertical]) {
                calendarGrid
                    .padding(16)
            }
        }
        .task(id: displayYear) { await loadNonSchoolDays() }
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

    // MARK: - Non-School Day Loading

    private func loadNonSchoolDays() async {
        let cal = AppCalendar.shared
        var startComps = DateComponents()
        startComps.year = displayYear
        startComps.month = 1
        startComps.day = 1
        guard let start = cal.date(from: startComps),
              let end = cal.date(byAdding: .year, value: 1, to: start) else { return }

        let dates = await SchoolCalendar.nonSchoolDays(in: start..<end, using: modelContext)
        var cells = Set<CellID>()
        for date in dates {
            let m = cal.component(.month, from: date)
            let d = cal.component(.day, from: date)
            cells.insert(CellID(month: m, day: d))
        }
        await MainActor.run { nonSchoolCells = cells }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(1...12, id: \.self) { month in
                monthColumn(month: month)
                if month < 12 {
                    Divider()
                }
            }
        }
    }

    private func monthColumn(month: Int) -> some View {
        let days = daysInMonth(month)

        return VStack(spacing: 0) {
            Text(Self.monthNames[month - 1])
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))

            Divider()

            ForEach(1...days, id: \.self) { day in
                dayRow(month: month, day: day)
                if day < days {
                    Divider()
                        .opacity(0.4)
                }
            }
        }
        .frame(width: 180)
    }

    /// Actual days in month for the selected year (handles leap years)
    private func daysInMonth(_ month: Int) -> Int {
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = displayYear
        comps.month = month
        comps.day = 1
        guard let date = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    // MARK: - Day Row

    private func dayRow(month: Int, day: Int) -> some View {
        let cellID = CellID(month: month, day: day)
        let holiday = PerpetualHolidays.holiday(month: month, day: day, year: displayYear)
        let note = notesLookup[cellID]
        let displayText = note?.text ?? holiday ?? ""
        let isEditing = editingCell == cellID
        let isHoliday = holiday != nil && (note == nil || note?.text.isEmpty == true)
        let isToday = isTodayCell(month: month, day: day)
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

    private func isTodayCell(month: Int, day: Int) -> Bool {
        let now = Date()
        let cal = AppCalendar.shared
        return cal.component(.year, from: now) == displayYear
            && cal.component(.month, from: now) == month
            && cal.component(.day, from: now) == day
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
        let holiday = PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: displayYear)

        if let existing = notesLookup[cellID] {
            if trimmed.isEmpty || trimmed == holiday {
                modelContext.delete(existing)
            } else {
                existing.text = trimmed
                existing.modifiedAt = Date()
            }
        } else if !trimmed.isEmpty && trimmed != holiday {
            let note = CalendarNote(year: displayYear, month: cellID.month, day: cellID.day, text: trimmed)
            modelContext.insert(note)
        }

        modelContext.safeSave()
        editingCell = nil
        editText = ""
    }
}

// MARK: - Cell Identifier

private struct CellID: Hashable {
    let month: Int
    let day: Int
}

// MARK: - US Federal Holidays

/// Fixed-date and floating US federal holidays.
enum PerpetualHolidays {
    static func holiday(month: Int, day: Int, year: Int) -> String? {
        // Fixed-date holidays
        switch (month, day) {
        case (1, 1):   return "New Year's Day"
        case (6, 19):  return "Juneteenth"
        case (7, 4):   return "Independence Day"
        case (11, 11): return "Veterans Day"
        case (12, 25): return "Christmas Day"
        default: break
        }

        // Floating holidays require year to compute weekday
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
