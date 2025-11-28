import SwiftUI
import SwiftData

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
                case .lessons:
                    LessonsRootView()
                case .students:
                    StudentsRootView()
                case .planning:
                    PlanningRootView()
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

// MARK: - Root views for each tab

struct LessonsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @State private var selectedLesson: Lesson? = nil

    var body: some View {
        Group {
            if lessons.isEmpty {
                VStack(spacing: 8) {
                    Text("No lessons yet")
                        .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                    Text("Create your first lesson to get started.")
                        .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear(perform: seedSamplesOnce)
            } else {
                LessonsCardsGridView(
                    lessons: lessons,
                    isManualMode: false,
                    onTapLesson: { lesson in
                        selectedLesson = lesson
                    },
                    onReorder: nil
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if let selected = selectedLesson {
                ZStack {
                    // Dim background
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                selectedLesson = nil
                            }
                        }

                    // Centered card
                    LessonDetailCard(
                        lesson: selected,
                        onSave: { updated in
                            if let existing = lessons.first(where: { $0.id == updated.id }) {
                                existing.name = updated.name
                                existing.subject = updated.subject
                                existing.group = updated.group
                                existing.subheading = updated.subheading
                                existing.writeUp = updated.writeUp
                                try? modelContext.save()
                            }
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                selectedLesson = nil
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    ))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selectedLesson?.id)
            }
        }
    }

    private func seedSamplesOnce() {
        guard lessons.isEmpty else { return }
        let samples = [
            Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Intro to base-10", writeUp: "A foundational presentation of the decimal system."),
            Lesson(name: "Parts of Speech", subject: "Language", group: "Grammar", subheading: "Nouns and Verbs", writeUp: "Identify and classify parts of speech in simple sentences.")
        ]
        for l in samples { modelContext.insert(l) }
        try? modelContext.save()
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
