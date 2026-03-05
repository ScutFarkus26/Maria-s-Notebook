import SwiftUI
import SwiftData

/// Unified view showing the complete journey and progress for a lesson
struct LessonProgressView: View {
    let lesson: Lesson
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var modelContext

    @State var stats: LessonStats?
    @State var presentations: [Presentation] = []
    @State var allWork: [WorkModel] = []
    @State var practiceSessions: [PracticeSession] = []
    @State var isLoading = true
    @State private var selectedTab: ProgressTab = .overview

    enum ProgressTab: String, CaseIterable {
        case overview = "Overview"
        case presentations = "Presentations"
        case work = "Work"
        case practice = "Practice"

        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .presentations: return "calendar.badge.checkmark"
            case .work: return "folder.badge.gearshape"
            case .practice: return "person.2.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Tab selector
            tabSelector

            Divider()

            // Content
            ScrollView {
                if isLoading {
                    ProgressView()
                        .padding(.top, 60)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 0) {
                        switch selectedTab {
                        case .overview:
                            overviewContent
                        case .presentations:
                            presentationsContent
                        case .work:
                            workContent
                        case .practice:
                            practiceContent
                        }
                    }
                    .padding(AppTheme.Spacing.large)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 600)
        #endif
        .task {
            await loadData()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text(lesson.name)
                    .font(AppTheme.ScaledFont.titleMedium)

                HStack(spacing: AppTheme.Spacing.small) {
                    if !lesson.subject.isEmpty {
                        StatusPill(text: lesson.subject, color: .blue, icon: nil)
                    }

                    if !lesson.group.isEmpty {
                        StatusPill(text: lesson.group, color: .purple, icon: nil)
                    }
                }
            }

            Spacer()

            Button("Done") {
                onDone?() ?? dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .padding(.vertical, AppTheme.Spacing.medium)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(ProgressTab.allCases, id: \.self) { tab in
                Button {
                    adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.verySmall) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.rawValue)
                            .font(AppTheme.ScaledFont.bodySemibold)
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                    .padding(.horizontal, AppTheme.Spacing.medium)
                    .padding(.vertical, AppTheme.Spacing.small + 2)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
    }

    // MARK: - Data Loading

    private func loadData() async {
        stats = lesson.getLessonStats(from: modelContext)
        presentations = lesson.fetchAllPresentations(from: modelContext)
        allWork = lesson.fetchAllWork(from: modelContext)
        practiceSessions = lesson.fetchAllPracticeSessions(from: modelContext)

        await MainActor.run {
            isLoading = false
        }
    }
}
