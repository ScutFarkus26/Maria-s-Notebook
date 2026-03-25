import SwiftUI

struct DayHeaderView: View {
    let name: String
    let number: String
    let nonSchool: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.headline.weight(.semibold))
            Text(number)
                .font(.title2.weight(.semibold))
            Spacer()
            if nonSchool {
                Text("No School")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct AgendaView<Content: View, TopBar: View, Preface: View, Header: View>: View {
    let days: [Date]
    let dayID: (Date) -> String
    let dayHeader: (Date) -> Header
    @ViewBuilder let topBar: (_ scrollToDay: @escaping (Date) -> Void) -> TopBar
    @ViewBuilder let preface: () -> Preface
    @ViewBuilder let contentForDay: (Date) -> Content

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                Divider()

                // Optional top bar (e.g., day strip) with access to scrollToDay
                topBar { day in
                    _ = adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        proxy.scrollTo(dayID(day), anchor: .top)
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                        // Optional preface section (e.g., Overdue)
                        preface()

                        ForEach(days, id: \.self) { day in
                            Section(header: dayHeader(day)) {
                                contentForDay(day)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                            }
                            .id(dayID(day))
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .onAppear {
                if let firstDay = days.first {
                    proxy.scrollTo(dayID(firstDay), anchor: .top)
                }
            }
        }
    }
}
extension AgendaView where TopBar == EmptyView, Preface == EmptyView {
    init(
        days: [Date],
        dayID: @escaping (Date) -> String,
        dayHeader: @escaping (Date) -> Header,
        @ViewBuilder contentForDay: @escaping (Date) -> Content
    ) {
        self.days = days
        self.dayID = dayID
        self.dayHeader = dayHeader
        self.topBar = { _ in EmptyView() }
        self.preface = { EmptyView() }
        self.contentForDay = contentForDay
    }
}
