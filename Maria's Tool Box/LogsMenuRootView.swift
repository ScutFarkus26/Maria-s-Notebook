import SwiftUI

struct LogsMenuRootView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case lessons = "Lessons Log"
        case presentations = "Presentation History"
        case works = "Works Log"
        // Future: add other logs here
        var id: String { rawValue }
    }

    @AppStorage("LogsMenuRootView.mode") private var modeRaw: String = Mode.lessons.rawValue
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .lessons }

    var body: some View {
        VStack(spacing: 0) {
            // Top pill navigation for logs
            #if os(iOS)
            Group {
                if horizontalSizeClass == .compact {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            PillNavButton(title: Mode.lessons.rawValue, isSelected: mode == .lessons) { modeRaw = Mode.lessons.rawValue }
                            PillNavButton(title: Mode.presentations.rawValue, isSelected: mode == .presentations) { modeRaw = Mode.presentations.rawValue }
                            PillNavButton(title: Mode.works.rawValue, isSelected: mode == .works) { modeRaw = Mode.works.rawValue }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                } else {
                    HStack {
                        Spacer()
                        HStack(spacing: 12) {
                            PillNavButton(title: Mode.lessons.rawValue, isSelected: mode == .lessons) { modeRaw = Mode.lessons.rawValue }
                            PillNavButton(title: Mode.presentations.rawValue, isSelected: mode == .presentations) { modeRaw = Mode.presentations.rawValue }
                            PillNavButton(title: Mode.works.rawValue, isSelected: mode == .works) { modeRaw = Mode.works.rawValue }
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
            #else
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    PillNavButton(title: Mode.lessons.rawValue, isSelected: mode == .lessons) { modeRaw = Mode.lessons.rawValue }
                    PillNavButton(title: Mode.presentations.rawValue, isSelected: mode == .presentations) { modeRaw = Mode.presentations.rawValue }
                    PillNavButton(title: Mode.works.rawValue, isSelected: mode == .works) { modeRaw = Mode.works.rawValue }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            #endif

            Divider()

            Group {
                switch mode {
                case .lessons:
                    StudentLessonsRootView()
                case .presentations:
                    PresentationHistoryView()
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
