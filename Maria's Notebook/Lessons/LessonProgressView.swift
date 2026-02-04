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
                    .padding(24)
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
            VStack(alignment: .leading, spacing: 6) {
                Text(lesson.name)
                    .font(.system(size: AppTheme.FontSize.titleMedium, weight: .bold, design: .rounded))
                
                HStack(spacing: 8) {
                    if !lesson.subject.isEmpty {
                        Text(lesson.subject)
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.blue.opacity(0.1)))
                    }
                    
                    if !lesson.group.isEmpty {
                        Text(lesson.group)
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.purple.opacity(0.1)))
                    }
                }
            }
            
            Spacer()
            
            Button("Done") {
                onDone?() ?? dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(ProgressTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
    }
    
    // MARK: - Overview Tab
    
    @ViewBuilder
    private var overviewContent: some View {
        if let stats = stats {
            VStack(spacing: 24) {
                // Stats cards
                statsCards(stats: stats)
                
                // Journey timeline
                VStack(alignment: .leading, spacing: 12) {
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
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
    }
    
    @ViewBuilder
    private func quickInsights(stats: LessonStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
            
            VStack(alignment: .leading, spacing: 8) {
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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
            
            Text(text)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
    }
    
    // MARK: - Presentations Tab
    
    @ViewBuilder
    private var presentationsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(presentation.isPresented ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: presentation.isPresented ? "checkmark.circle.fill" : "calendar")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(presentation.isPresented ? .green : .blue)
                }
                
                VStack(alignment: .leading, spacing: 3) {
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
                Text("\(students.count) \(students.count == 1 ? "student" : "students")")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
            
            // Related work summary
            let work = allWork.filter { $0.presentationID == presentation.id.uuidString }
            if !work.isEmpty {
                HStack(spacing: 6) {
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Work Tab
    
    @ViewBuilder
    private var workContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(work.status.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: work.status.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(work.status.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                
                HStack(spacing: 6) {
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
            
            Text(work.status.displayName)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(work.status.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(work.status.color.opacity(0.12)))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Practice Tab
    
    @ViewBuilder
    private var practiceContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.isGroupSession ? "Group Practice" : "Solo Practice")
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let duration = session.durationFormatted {
                    Text(duration)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                }
            }
            
            // Students
            let students = session.fetchStudents(from: modelContext)
            if !students.isEmpty {
                HStack(spacing: 6) {
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple.opacity(0.05))
        )
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: 6) {
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
