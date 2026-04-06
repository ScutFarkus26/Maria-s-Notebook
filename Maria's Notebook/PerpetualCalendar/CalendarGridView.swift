import SwiftUI

// MARK: - Reusable Calendar Grid

/// A generic perpetual calendar grid: months as horizontal columns, days 1-31 as rows.
/// The caller supplies a `dayContent` closure to render each day cell.
struct CalendarGridView<DayContent: View, HeaderTrailing: View>: View {
    let title: String
    let columnWidth: CGFloat
    let yearRange: ClosedRange<Int>
    let nonSchoolCells: Set<CellID>
    @ViewBuilder let headerTrailing: () -> HeaderTrailing
    @ViewBuilder let dayContent: (CellID, Bool, Bool) -> DayContent

    @State private var displayYear: Int
    @State private var scrollProxy: ScrollViewProxy?
    @State private var suppressYearScroll = false
    @State private var programmaticScrollInFlight = false

    init(
        title: String,
        columnWidth: CGFloat = 164,
        yearRange: ClosedRange<Int>,
        nonSchoolCells: Set<CellID>,
        @ViewBuilder headerTrailing: @escaping () -> HeaderTrailing,
        @ViewBuilder dayContent: @escaping (CellID, Bool, Bool) -> DayContent
    ) {
        self.title = title
        self.columnWidth = columnWidth
        self.yearRange = yearRange
        self.nonSchoolCells = nonSchoolCells
        self.headerTrailing = headerTrailing
        self.dayContent = dayContent
        _displayYear = State(initialValue: Calendar.current.component(.year, from: Date()))
    }

    private var allMonths: [MonthID] {
        yearRange.flatMap { year in
            (1...12).map { MonthID(year: year, month: $0) }
        }
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
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))

            Spacer()

            headerTrailing()

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

    // MARK: - Grid

    private var calendarGrid: some View {
        LazyHStack(alignment: .top, spacing: 0) {
            ForEach(allMonths) { monthID in
                monthColumn(monthID)
                    .id(monthID)
                    .onAppear { trackVisibleYear(monthID) }
            }
        }
    }

    private func trackVisibleYear(_ monthID: MonthID) {
        guard !programmaticScrollInFlight else { return }
        if monthID.month <= 6 && monthID.year != displayYear {
            displayYear = monthID.year
        }
    }

    private func monthColumn(_ monthID: MonthID) -> some View {
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
                let cellID = CellID(year: monthID.year, month: monthID.month, day: day)
                dayContent(cellID, isTodayCell(cellID), nonSchoolCells.contains(cellID))
            }
        }
        .frame(width: columnWidth)
    }

    // MARK: - Helpers

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

    func isTodayCell(_ cellID: CellID) -> Bool {
        let now = Date()
        let cal = AppCalendar.shared
        return cal.component(.year, from: now) == cellID.year
            && cal.component(.month, from: now) == cellID.month
            && cal.component(.day, from: now) == cellID.day
    }

    // MARK: - Scroll

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
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            programmaticScrollInFlight = false
        }
    }

    private func todayOffsetTarget() -> MonthID {
        let cal = AppCalendar.shared
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        if m > 2 {
            return MonthID(year: y, month: m - 2)
        } else {
            return MonthID(year: y - 1, month: m + 10)
        }
    }
}

// MARK: - Convenience initializer (no header trailing)

extension CalendarGridView where HeaderTrailing == EmptyView {
    init(
        title: String,
        columnWidth: CGFloat = 164,
        yearRange: ClosedRange<Int>,
        nonSchoolCells: Set<CellID>,
        @ViewBuilder dayContent: @escaping (CellID, Bool, Bool) -> DayContent
    ) {
        self.init(
            title: title,
            columnWidth: columnWidth,
            yearRange: yearRange,
            nonSchoolCells: nonSchoolCells,
            headerTrailing: { EmptyView() },
            dayContent: dayContent
        )
    }
}
