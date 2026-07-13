import SwiftUI

/// A single doorway for learning work. The menu gives long-running planning and
/// history their proper names without bringing back a second row of custom tabs.
struct StudentLearningWorkspace: View {
    private enum Destination: String {
        case current
        case plan
        case history

        var title: String {
            switch self {
            case .current: "Current Learning"
            case .plan: "Year Plan"
            case .history: "Past Learning"
            }
        }

        var systemImage: String {
            switch self {
            case .current: "book.closed"
            case .plan: "calendar"
            case .history: "clock.arrow.circlepath"
            }
        }
    }

    let student: CDStudent
    @State private var destination: Destination = .current

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(destination.title, systemImage: destination.systemImage)
                    .font(.headline)
                Spacer()
                Menu {
                    ForEach([Destination.current, .plan, .history], id: \.rawValue) { item in
                        Button(item.title, systemImage: item.systemImage) {
                            destination = item
                        }
                    }
                } label: {
                    Label("Learning View", systemImage: "rectangle.3.group")
                }
                .help("Choose a learning view")
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 8)

            Divider()

            switch destination {
            case .current:
                StudentProgressTab(student: student)
            case .plan:
                StudentYearPlanTab(student: student)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            case .history:
                StudentHistoryTab(student: student)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
    }
}
