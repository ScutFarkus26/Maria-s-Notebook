import SwiftUI

struct LogsMenuRootView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case lessons = "Lessons Log"
        case works = "Works Log"
        // Future: add other logs here
        var id: String { rawValue }
    }

    @AppStorage("LogsMenuRootView.mode") private var modeRaw: String = Mode.lessons.rawValue
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .lessons }

    var body: some View {
        VStack(spacing: 0) {
            // Top pill navigation for logs
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    PillNavButton(title: Mode.lessons.rawValue, isSelected: mode == .lessons) {
                        modeRaw = Mode.lessons.rawValue
                    }
                    PillNavButton(title: Mode.works.rawValue, isSelected: mode == .works) {
                        modeRaw = Mode.works.rawValue
                    }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch mode {
                case .lessons:
                    StudentLessonsRootView()
                case .works:
                    WorksLogView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    LogsMenuRootView()
}
