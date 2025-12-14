import SwiftUI

public struct UnifiedAgendaView<Sidebar: View, HeaderActions: View, DayContent: View, Preface: View>: View {
    @Environment(\.calendar) private var calendar

    private let startDate: Date
    private let days: [Date]
    private let isNonSchoolDay: (Date) -> Bool
    private let onPrev: () -> Void
    private let onNext: () -> Void
    private let onToday: () -> Void
    private let sidebar: () -> Sidebar
    private let headerActions: () -> HeaderActions
    private let preface: () -> Preface
    private let dayContent: (Date) -> DayContent

    public init(
        startDate: Date,
        days: [Date],
        isNonSchoolDay: @escaping (Date) -> Bool,
        onPrev: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onToday: @escaping () -> Void,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder headerActions: @escaping () -> HeaderActions,
        @ViewBuilder preface: @escaping () -> Preface = { EmptyView() },
        @ViewBuilder dayContent: @escaping (Date) -> DayContent
    ) {
        self.startDate = startDate
        self.days = days
        self.isNonSchoolDay = isNonSchoolDay
        self.onPrev = onPrev
        self.onNext = onNext
        self.onToday = onToday
        self.sidebar = sidebar
        self.headerActions = headerActions
        self.preface = preface
        self.dayContent = dayContent
    }

    public var body: some View {
        AgendaShellView(
            sidebar: sidebar,
            header: {
                AgendaWeekHeaderView(
                    startDate: startDate,
                    days: days,
                    onPrev: onPrev,
                    onNext: onNext,
                    onToday: onToday,
                    actions: headerActions
                )
            },
            content: {
                ScrollViewReader { proxy in
                    VStack(spacing: 8) {
                        AgendaDayStripView(days: days) { day in
                            withAnimation {
                                proxy.scrollTo(dayID(day), anchor: .top)
                            }
                        }
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                                preface()
                                ForEach(days, id: \.self) { day in
                                    Section(
                                        header:
                                            HStack {
                                                AgendaDaySectionHeaderView(day: day, isNonSchoolDay: isNonSchoolDay(day))
                                            }
                                            .background(.bar)
                                    ) {
                                        dayContent(day)
                                    }
                                    .id(dayID(day))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                    }
                }
            }
        )
    }

    private func dayID(_ day: Date) -> String {
        let start = calendar.startOfDay(for: day)
        return "day_\(Int(start.timeIntervalSince1970))"
    }
}

#if DEBUG
struct UnifiedAgendaView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedAgendaView(
            startDate: Date(),
            days: [Date(), Calendar.current.date(byAdding: .day, value: 1, to: Date())!],
            isNonSchoolDay: { _ in false },
            onPrev: {},
            onNext: {},
            onToday: {},
            sidebar: { EmptyView() },
            headerActions: { EmptyView() },
            preface: { EmptyView() }
        ) { day in
            Text("Content for \(day, style: .date)")
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
        }
    }
}
#endif
