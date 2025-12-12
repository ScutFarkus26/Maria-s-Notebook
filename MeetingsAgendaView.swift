import SwiftUI

struct MeetingsAgendaView: View {
    @State private var viewModel = MeetingsAgendaViewModel()
    @Environment(\.calendar) private var calendar

    var body: some View {
        let days = viewModel.days
        return AgendaShellView(
            sidebar: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Meetings")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .frame(width: 280)
            },
            header: {
                VStack(spacing: 0) {
                    AgendaWeekHeaderView(
                        startDate: viewModel.startDate,
                        days: days,
                        onPrev: { withAnimation { viewModel.move(by: -5) } },
                        onNext: { withAnimation { viewModel.move(by: 5) } },
                        onToday: { withAnimation { viewModel.resetToToday() } },
                        actions: { EmptyView() }
                    )
                    AgendaDayStripView(days: days) { day in
                        viewModel.scrollToDay = day
                    }
                }
            },
            content: {
                ScrollViewReader { proxy in
                    AgendaView(
                        days: days,
                        dayID: { day in viewModel.dayID(day) },
                        dayHeader: { day in AgendaDaySectionHeaderView(day: day, isNonSchoolDay: false) },
                        contentForDay: { day in
                            VStack(alignment: .leading, spacing: 12) {
                                AgendaPeriodChipView(period: .morning)
                                Text("No meetings")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                    .onChange(of: viewModel.scrollToDay) { _, new in
                        if let d = new { withAnimation { proxy.scrollTo(viewModel.dayID(d), anchor: .top) } }
                    }
                }
            }
        )
    }
}

#Preview {
    MeetingsAgendaView()
}
