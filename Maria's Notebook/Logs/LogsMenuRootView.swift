import SwiftUI

struct LogsMenuRootView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case presentations = "Presentations"
        case works = "Works"
        case attendance = "Attendance"
        case meetings = "Meetings"
        case observations = "Observations"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .presentations: return "calendar.badge.clock"
            case .works: return "hammer.fill"
            case .attendance: return "checklist"
            case .meetings: return "person.2.circle"
            case .observations: return "eye.fill"
            }
        }

        var color: Color {
            switch self {
            case .presentations: return .purple
            case .works: return .orange
            case .attendance: return .green
            case .meetings: return .blue
            case .observations: return .teal
            }
        }
    }

    @AppStorage(UserDefaultsKeys.logsMenuRootViewMode) private var modeRaw: String = Mode.presentations.rawValue

    private var mode: Mode {
        get { Mode(rawValue: modeRaw) ?? .presentations }
        nonmutating set { modeRaw = newValue.rawValue }
    }

    private var selectedMode: Binding<Mode?> {
        Binding(
            get: { mode },
            set: { newValue in
                if let newValue {
                    modeRaw = newValue.rawValue
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Logs")
            Divider()
            HStack(spacing: 0) {
                // MARK: Sidebar
                logsSidebar
                    .frame(width: 280)

                Divider()

                // MARK: Content Area
                logsContent
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sidebar

    private var logsSidebar: some View {
        List(selection: selectedMode) {
            ForEach(Mode.allCases) { logMode in
                LogsSidebarRow(mode: logMode)
                    .tag(logMode)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Logs")
    }

    // MARK: - Content

    @ViewBuilder
    private var logsContent: some View {
        switch mode {
        case .presentations:
            // CDLessonAssignment history view for presentation logs
            LessonAssignmentHistoryView()
        case .works:
            WorksLogView()
        case .attendance:
            AttendanceLogView()
        case .meetings:
            MeetingsLogView()
        case .observations:
            ObservationsView()
        }
    }
}

// MARK: - Sidebar Row

/// A row component for displaying a log type in the sidebar.
/// Shows the log's icon (colored circle with glyph) and title.
/// Design matches SubjectListRow/StudentListRow/ProjectSidebarRow for visual consistency.
struct LogsSidebarRow: View {
    let mode: LogsMenuRootView.Mode

    var body: some View {
        HStack(spacing: 12) {
            // Icon circle with log-specific glyph
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [mode.color.opacity(UIConstants.OpacityConstants.heavy), mode.color]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 24
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: mode.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Title
            Text(mode.rawValue)
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    LogsMenuRootView()
}
