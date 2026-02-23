import SwiftUI
import SwiftData

/// Unified view showing the complete journey and progress for a lesson
struct LessonProgressView: View {
    let lesson: Lesson
    var onDone: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var stats: LessonStats? = nil
    @State private var presentations: [Presentation] = []
    @State private var allWork: [WorkModel] = []
    @State private var practiceSessions: [PracticeSession] = []
    @State private var isLoading = true
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
                    .font(.system(size: AppTheme.FontSize.titleMedium, weight: .bold, design: .rounded))
                
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
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.verySmall) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
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
    
    // MARK: - Overview Tab
    
    @ViewBuilder
    private var overviewContent: some View {
        if let stats = stats {
            VStack(spacing: AppTheme.Spacing.large) {
                // Stats cards
                statsCards(stats: stats)
                
                // Journey timeline
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    Text("Lesson Journey")
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
                    
                    LessonJourneyTimeline(lesson: lesson, modelContext: modelContext)
                        .frame(height: 350)
                }
                
                // Quick insights
                quickInsights(stats: stats)
            }
        }
    }
    
    @ViewBuilder
    private func statsCards(stats: LessonStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.medium) {
            statCard(
                title: "Presentations",
                value: "\(stats.presentedCount)",
                subtitle: "\(stats.scheduledCount) scheduled",
                icon: "calendar.badge.checkmark",
                color: .green
            )
            
            statCard(
                title: "Work Items",
                value: "\(stats.completedWorkItems)/\(stats.totalWorkItems)",
                subtitle: stats.totalWorkItems > 0 ? "\(Int(stats.workCompletionRate * 100))% complete" : "No work yet",
                icon: "folder.badge.gearshape",
                color: .blue
            )
            
            statCard(
                title: "Active Work",
                value: "\(stats.activeWorkItems)",
                subtitle: stats.activeWorkItems == 0 ? "All caught up!" : "In progress",
                icon: "circle.dashed",
                color: .orange
            )
            
            statCard(
                title: "Practice Sessions",
                value: "\(stats.totalPracticeSessions)",
                subtitle: stats.totalPracticeSessions > 0 ? "Last: \(stats.lastPresentedDate?.formatted(date: .abbreviated, time: .omitted) ?? "N/A")" : "None yet",
                icon: "person.2.fill",
                color: .purple
            )
        }
    }
    
    @ViewBuilder
    private func statCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: AppTheme.FontSize.titleLarge, weight: .bold, design: .rounded))
                
                Text(title)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Text(subtitle)
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .fill(color.opacity(UIConstants.OpacityConstants.faint))
        )
    }
    
    @ViewBuilder
    private func quickInsights(stats: LessonStats) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Insights")
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                if stats.activeWorkItems > 0 {
                    insightRow(
                        icon: "exclamationmark.circle",
                        text: "\(stats.activeWorkItems) work \(stats.activeWorkItems == 1 ? "item" : "items") still in progress",
                        color: .orange
                    )
                }
                
                if stats.workCompletionRate == 1.0 && stats.totalWorkItems > 0 {
                    insightRow(
                        icon: "checkmark.circle.fill",
                        text: "All work completed! Great progress.",
                        color: .green
                    )
                }
                
                if stats.totalPracticeSessions == 0 && stats.totalWorkItems > 0 {
                    insightRow(
                        icon: "info.circle",
                        text: "No practice sessions recorded yet",
                        color: .blue
                    )
                }
                
                if stats.totalPresentations > 0 && stats.totalWorkItems == 0 {
                    insightRow(
                        icon: "arrow.forward.circle",
                        text: "Consider creating follow-up work",
                        color: .purple
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private func insightRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: AppTheme.Spacing.small + 2) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
            
            Text(text)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(AppTheme.Spacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium + 2)
                .fill(color.opacity(UIConstants.OpacityConstants.faint))
        )
    }
    
    // MARK: - Presentations Tab
    
    @ViewBuilder
    private var presentationsContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if presentations.isEmpty {
                emptyStateView(
                    icon: "calendar.badge.clock",
                    title: "No Presentations",
                    message: "This lesson hasn't been presented yet"
                )
            } else {
                ForEach(presentations) { presentation in
                    presentationRow(presentation)
                }
            }
        }
    }
    
    @ViewBuilder
    private func presentationRow(_ presentation: Presentation) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.compact) {
                ZStack {
                    Circle()
                        .fill(presentation.isPresented ? Color.green.opacity(UIConstants.OpacityConstants.accent) : Color.blue.opacity(UIConstants.OpacityConstants.accent))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: presentation.isPresented ? "checkmark.circle.fill" : "calendar")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(presentation.isPresented ? .green : .blue)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall + 1) {
                    Text(presentation.isPresented ? "Presented" : presentation.isScheduled ? "Scheduled" : "Draft")
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    
                    if let date = presentation.presentedAt ?? presentation.scheduledFor {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                let students = presentation.fetchStudents(from: modelContext)
                StatusPill(
                    text: "\(students.count) \(students.count == 1 ? "student" : "students")",
                    color: .secondary,
                    icon: nil
                )
            }
            
            // Related work summary
            let work = allWork.filter { $0.presentationID == presentation.id.uuidString }
            if !work.isEmpty {
                HStack(spacing: AppTheme.Spacing.verySmall) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    let completed = work.filter { $0.status == .complete }.count
                    Text("\(work.count) work \(work.count == 1 ? "item" : "items") (\(completed) complete)")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 56)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.light), lineWidth: UIConstants.StrokeWidth.thin)
        )
    }
    
    // MARK: - Work Tab
    
    @ViewBuilder
    private var workContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if allWork.isEmpty {
                emptyStateView(
                    icon: "folder.badge.gearshape",
                    title: "No Work Items",
                    message: "No work has been created for this lesson yet"
                )
            } else {
                ForEach(allWork) { work in
                    workRow(work)
                }
            }
        }
    }
    
    @ViewBuilder
    private func workRow(_ work: WorkModel) -> some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            ZStack {
                Circle()
                    .fill(work.status.color.opacity(UIConstants.OpacityConstants.accent))
                    .frame(width: 44, height: 44)
                
                Image(systemName: work.status.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(work.status.color)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Text(work.title)
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))

                HStack(spacing: AppTheme.Spacing.verySmall) {
                    if let student = work.fetchStudent(from: modelContext) {
                        Text(StudentFormatter.displayName(for: student))
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    if let kind = work.kind {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(kind.displayName)
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            StatusPill(
                text: work.status.displayName,
                color: work.status.color,
                icon: nil
            )
        }
        .padding(AppTheme.Spacing.compact + 2)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium + 2)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium + 2)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.faint), lineWidth: UIConstants.StrokeWidth.thin)
        )
    }
    
    // MARK: - Practice Tab
    
    @ViewBuilder
    private var practiceContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if practiceSessions.isEmpty {
                emptyStateView(
                    icon: "person.2.fill",
                    title: "No Practice Sessions",
                    message: "No practice sessions have been recorded for this lesson"
                )
            } else {
                ForEach(practiceSessions) { session in
                    practiceSessionRow(session)
                }
            }
        }
    }
    
    @ViewBuilder
    private func practiceSessionRow(_ session: PracticeSession) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small + 2) {
            HStack(spacing: AppTheme.Spacing.compact) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(UIConstants.OpacityConstants.accent))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall + 1) {
                    Text(session.isGroupSession ? "Group Practice" : "Solo Practice")
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let duration = session.durationFormatted {
                    StatusPill(
                        text: duration,
                        color: .secondary,
                        icon: nil
                    )
                }
            }
            
            // Students
            let students = session.fetchStudents(from: modelContext)
            if !students.isEmpty {
                HStack(spacing: AppTheme.Spacing.verySmall) {
                    Image(systemName: "person.2")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    Text(students.map { StudentFormatter.displayName(for: $0) }.joined(separator: ", "))
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(AppTheme.Spacing.compact + 2)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium + 2)
                .fill(Color.purple.opacity(UIConstants.OpacityConstants.veryFaint + 0.01))
        )
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)

            VStack(spacing: AppTheme.Spacing.verySmall) {
                Text(title)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Text(message)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
