import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case students = "Students"
        case lessons = "Albums"         // Lessons library (albums view)
        case planning = "Planning"
        case studentLessons = "Lessons" // Student lessons (pills)
        case work = "Work"
        case settings = "Settings"

        var id: String { rawValue }
    }

    @State private var selectedTab: Tab = .lessons

    var body: some View {
        VStack(spacing: 0) {
            // Top pill navigation
            HStack {
                Spacer()

                HStack(spacing: 12) {
                    ForEach(Tab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .frame(minHeight: 30)
                                .background(pillBackground(for: tab))
                                .foregroundStyle(pillForeground(for: tab))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Active view
            Group {
                switch selectedTab {
                case .studentLessons:
                    StudentLessonsRootView()
                case .lessons:
                    LessonsRootView()
                case .students:
                    StudentsRootView()
                case .planning:
                    PlanningRootView()
                case .work:
                    WorkView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Styling

    private func pillBackground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color.platformBackground)
        }
    }

    private func pillForeground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.white)
        } else {
            return AnyShapeStyle(Color.primary)
        }
    }
}

struct PlanningRootView: View {
    var body: some View {
        PlanningWeekView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

