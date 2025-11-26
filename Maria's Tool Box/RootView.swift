import SwiftUI

struct RootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case lessons = "Lessons"
        case students = "Students"
        case planning = "Planning"
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
                                .font(.system(size: 14, weight: .semibold))
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
                case .lessons:
                    LessonsRootView()
                case .students:
                    StudentsRootView()
                case .planning:
                    PlanningRootView()
                case .settings:
                    SettingsRootView()
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
            return AnyShapeStyle(Color(NSColor.windowBackgroundColor))
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

// MARK: - Root views for each tab

struct LessonsRootView: View {
    var body: some View {
        Text("Lessons View")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StudentsRootView: View {
    var body: some View {
        StudentsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlanningRootView: View {
    var body: some View {
        Text("Planning View")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsRootView: View {
    var body: some View {
        Text("Settings View")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView()
}
