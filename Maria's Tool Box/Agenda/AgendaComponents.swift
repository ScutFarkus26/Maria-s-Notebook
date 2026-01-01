import SwiftUI

struct AgendaShellView<Sidebar: View, Header: View, Content: View>: View {
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    init(
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.sidebar = sidebar
        self.header = header
        self.content = content
    }

    @State private var showSidebarSheet: Bool = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            VStack(spacing: 0) {
                // Compact top bar with Sidebar trigger
                HStack(spacing: 12) {
                    Button {
                        showSidebarSheet = true
                    } label: {
                        Label("Inbox", systemImage: "tray.full")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()

                VStack(spacing: 0) {
                    header()
                    Divider()
                    content()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .sheet(isPresented: $showSidebarSheet) {
                NavigationStack {
                    sidebar()
                        .navigationTitle("Inbox")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showSidebarSheet = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        } else {
            HStack(spacing: 0) {
                sidebar()
                    .frame(width: 280)
                Divider()
                VStack(spacing: 0) {
                    header()
                    Divider()
                    content()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #else
        HStack(spacing: 0) {
            sidebar()
                .frame(width: 280)
            Divider()
            VStack(spacing: 0) {
                header()
                Divider()
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #endif
    }
}

struct AgendaWeekHeaderView<Actions: View>: View {
    let startDate: Date
    let days: [Date]
    let onPrev: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void
    
    let actions: () -> Actions
    
    init(startDate: Date, days: [Date], onPrev: @escaping () -> Void, onNext: @escaping () -> Void, onToday: @escaping () -> Void, @ViewBuilder actions: @escaping () -> Actions) {
        self.startDate = startDate
        self.days = days
        self.onPrev = onPrev
        self.onNext = onNext
        self.onToday = onToday
        self.actions = actions
    }

    private var weekRangeText: String {
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        let first = days.first ?? startDate
        let last = days.last ?? startDate
        return "\(first.formatted(fmt)) - \(last.formatted(fmt))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onPrev()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            Spacer()
            Text(weekRangeText)
                .font(.title3.weight(.semibold))
            Spacer()
            Button("Today", action: onToday)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                )
            HStack(spacing: 12) {
                actions()
                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

struct AgendaDayStripView: View {
    let days: [Date]
    let onTap: (Date) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(days, id: \.self) { day in
                    Button {
                        onTap(day)
                    } label: {
                        Text(day.formatted(Date.FormatStyle().weekday(.abbreviated).day()))
                            .font(.callout.weight(.semibold))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

struct AgendaDaySectionHeaderView: View {
    let day: Date
    let isNonSchoolDay: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(day.formatted(Date.FormatStyle().weekday(.abbreviated)))
                .font(.headline.weight(.semibold))
            Text(day.formatted(Date.FormatStyle().day()))
                .font(.title2.weight(.semibold))
            Spacer()
            if isNonSchoolDay {
                Text("No School")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct AgendaPeriodChipView: View {
    let period: DayPeriod

    var body: some View {
        Text(period.label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(period.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(period.color.opacity(0.12))
            )
            .fixedSize()
    }
}

struct AgendaSchoolDayRules {
    static func computeInitialStartDate(calendar: Calendar, isNonSchoolDay: (Date) -> Bool) -> Date {
        // Centralize school-day movement rules in PlanningEngine to keep behavior consistent
        // across agenda-style views.
        let today = AppCalendar.startOfDay(Date())
        return PlanningEngine.firstSchoolDay(onOrAfter: today, calendar: calendar, isNonSchoolDay: isNonSchoolDay)
    }

    static func movedStart(bySchoolDays delta: Int, from start: Date, calendar: Calendar, isNonSchoolDay: (Date) -> Bool) -> Date {
        let startDay = AppCalendar.startOfDay(start)
        return PlanningEngine.moveBySchoolDays(from: startDay, days: delta, calendar: calendar, isNonSchoolDay: isNonSchoolDay)
    }
}

