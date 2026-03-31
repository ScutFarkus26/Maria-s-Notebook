import SwiftUI
import CoreData

// MARK: - Perpetual Calendar View

struct PerpetualCalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDCalendarNote.year, ascending: true), NSSortDescriptor(keyPath: \CDCalendarNote.month, ascending: true), NSSortDescriptor(keyPath: \CDCalendarNote.day, ascending: true)]) private var allNotes: FetchedResults<CDCalendarNote>

    @State private var displayYear: Int = Calendar.current.component(.year, from: Date())
    @State private var editingCell: CellID?
    @State private var editText: String = ""
    @State private var nonSchoolCells: Set<CellID> = []
    @State private var loadedYearRange: ClosedRange<Int>?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var suppressYearScroll = false
    @State private var programmaticScrollInFlight = false

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

    private var notesLookup: [CellID: CDCalendarNote] {
        var lookup: [CellID: CDCalendarNote] = [:]
        for note in allNotes {
            lookup[CellID(year: Int(note.year), month: Int(note.month), day: Int(note.day))] = note
        }
        return lookup
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    calendarGrid
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToCurrentMonth(proxy)
                }
                .onChange(of: displayYear) { _, newYear in
                    if suppressYearScroll {
                        suppressYearScroll = false
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(MonthID(year: newYear, month: 1), anchor: .leading)
                    }
                }
            }
        }
        .task { await loadNonSchoolDays() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Calendar")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))

            Spacer()

            HStack(spacing: 8) {
                Button {
                    displayYear -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text(String(displayYear))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Button {
                    displayYear += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button("Today") {
                    scrollToToday()
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.leading, 4)
            }
        }
        .padding()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    /// Scrolls so that the current month appears as the 3rd column by
    /// anchoring 2 months earlier to the leading edge.
    private func scrollToCurrentMonth(_ proxy: ScrollViewProxy) {
        let target = todayOffsetTarget()
        programmaticScrollInFlight = true
        suppressYearScroll = true
        displayYear = AppCalendar.shared.component(.year, from: Date())
        proxy.scrollTo(target, anchor: .leading)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            programmaticScrollInFlight = false
        }
    }

    private func scrollToToday() {
        guard let proxy = scrollProxy else { return }
        let target = todayOffsetTarget()
        programmaticScrollInFlight = true
        suppressYearScroll = true
        displayYear = AppCalendar.shared.component(.year, from: Date())
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(target, anchor: .leading)
        }
        // Allow trackVisibleYear to resume after the animation settles.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            programmaticScrollInFlight = false
        }
    }

    /// Returns the MonthID 2 months before today so today's month lands in column 3.
    private func todayOffsetTarget() -> MonthID {
        let cal = AppCalendar.shared
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        // Subtract 2 months, wrapping across year boundary
        if m > 2 {
            return MonthID(year: y, month: m - 2)
        } else {
            return MonthID(year: y - 1, month: m + 10)
        }
    }

}

// MARK: - Grid & Month Column

private extension PerpetualCalendarView {

    func loadNonSchoolDays() async {
        let cal = AppCalendar.shared
        let range = yearRange
        var startComps = DateComponents()
        startComps.year = range.lowerBound
        startComps.month = 1
        startComps.day = 1
        let years = range.upperBound - range.lowerBound + 1
        guard let start = cal.date(from: startComps),
              let end = cal.date(byAdding: .year, value: years, to: start) else { return }

        let dates = await SchoolCalendar.nonSchoolDays(in: start..<end, using: viewContext)
        var cells = Set<CellID>()
        for date in dates {
            cells.insert(CellID(
                year: cal.component(.year, from: date),
                month: cal.component(.month, from: date),
                day: cal.component(.day, from: date)
            ))
        }
        await MainActor.run {
            nonSchoolCells = cells
            loadedYearRange = range
        }
    }

    var calendarGrid: some View {
        LazyHStack(alignment: .top, spacing: 0) {
            ForEach(allMonths) { monthID in
                monthColumn(monthID)
                    .id(monthID)
                    .onAppear { trackVisibleYear(monthID) }
            }
        }
    }

    func trackVisibleYear(_ monthID: MonthID) {
        guard !programmaticScrollInFlight else { return }
        if monthID.month <= 6 && monthID.year != displayYear {
            displayYear = monthID.year
        }
    }

    func monthColumn(_ monthID: MonthID) -> some View {
        let days = daysInMonth(monthID)
        let abbrev = Calendar.current.shortMonthSymbols[monthID.month - 1].uppercased()

        return VStack(spacing: 0) {
            Text("\(abbrev) \(String(monthID.year))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 6)

            ForEach(1...days, id: \.self) { day in
                dayRow(monthID: monthID, day: day)
            }
        }
        .frame(width: 164)
    }

    func daysInMonth(_ monthID: MonthID) -> Int {
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = monthID.year
        comps.month = monthID.month
        comps.day = 1
        guard let date = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }
}

// MARK: - Day Row & Editing

private extension PerpetualCalendarView {

    func dayRow(monthID: MonthID, day: Int) -> some View {
        let cellID = CellID(year: monthID.year, month: monthID.month, day: day)
        let holiday = PerpetualHolidays.holiday(month: monthID.month, day: day, year: monthID.year)
        let note = notesLookup[cellID]
        let displayText = note?.text ?? holiday ?? ""
        let isEditing = editingCell == cellID
        let hasUserNote = note != nil && !(note?.text.isEmpty ?? true)
        let isHoliday = holiday != nil && !hasUserNote
        let isToday = isTodayCell(cellID)
        let isNoSchool = nonSchoolCells.contains(cellID)

        return HStack(spacing: 4) {
            Text("\(day)")
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(isToday ? Color.white : (isNoSchool ? Color.red.opacity(UIConstants.OpacityConstants.half) : Color.secondary))
                .frame(width: 22, height: 22)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    }
                }

            if isEditing {
                TextField("", text: $editText)
                    .font(.system(.caption, design: .rounded))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { commitEdit(cellID: cellID) }
            } else {
                Text(displayText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(textStyle(isHoliday: isHoliday, isNoSchool: isNoSchool))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginEdit(cellID: cellID, currentText: note?.text ?? holiday ?? "")
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
    }

    func textStyle(isHoliday: Bool, isNoSchool: Bool) -> some ShapeStyle {
        if isNoSchool { return AnyShapeStyle(.red.opacity(UIConstants.OpacityConstants.half)) }
        if isHoliday { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }

    func isTodayCell(_ cellID: CellID) -> Bool {
        let now = Date()
        let cal = AppCalendar.shared
        return cal.component(.year, from: now) == cellID.year
            && cal.component(.month, from: now) == cellID.month
            && cal.component(.day, from: now) == cellID.day
    }

    func beginEdit(cellID: CellID, currentText: String) {
        if let previous = editingCell, previous != cellID {
            commitEdit(cellID: previous)
        }
        editText = currentText
        editingCell = cellID
    }

    func commitEdit(cellID: CellID) {
        let trimmed = editText.trimmed()
        let holiday = PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year)

        if let existing = notesLookup[cellID] {
            if trimmed.isEmpty || trimmed == holiday {
                viewContext.delete(existing)
            } else {
                existing.text = trimmed
                existing.modifiedAt = Date()
            }
        } else if !trimmed.isEmpty && trimmed != holiday {
            let newNote = CDCalendarNote(context: viewContext)
            newNote.year = Int64(cellID.year)
            newNote.month = Int64(cellID.month)
            newNote.day = Int64(cellID.day)
            newNote.text = trimmed
        }

        viewContext.safeSave()
        editingCell = nil
        editText = ""
    }
}

// MARK: - Supporting Types

private struct MonthID: Hashable, Identifiable {
    let year: Int
    let month: Int
    var id: Int { year * 12 + month }
}

private struct CellID: Hashable {
    let year: Int
    let month: Int
    let day: Int
}

#Preview {
    PerpetualCalendarView()
        .previewEnvironment()
}
