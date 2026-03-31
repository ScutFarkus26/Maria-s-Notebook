import SwiftUI
import CoreData

// List view showing progress for all lessons, allowing selection to view detailed progress
// swiftlint:disable:next type_body_length
struct LessonProgressListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.subject, ascending: true), NSSortDescriptor(keyPath: \CDLesson.group, ascending: true), NSSortDescriptor(keyPath: \CDLesson.orderInGroup, ascending: true)])
    private var allLessons: FetchedResults<CDLesson>
    
    @State private var selectedLesson: CDLesson?
    @State private var searchText = ""
    @State private var selectedSubject: String?
    @State private var lessonStats: [UUID: LessonStats] = [:]
    @State private var isLoadingStats = true
    
    private var subjects: [String] {
        Array(Set(allLessons.map { $0.subject.trimmed() }))
            .filter { !$0.isEmpty }
            .sorted()
    }
    
    private var filteredLessons: [CDLesson] {
        var lessons = Array(allLessons)

        // Filter by subject
        if let selectedSubject {
            lessons = lessons.filter { $0.subject.trimmed() == selectedSubject }
        }

        // Filter by search
        if !searchText.isEmpty {
            lessons = lessons.filter { lesson in
                lesson.name.localizedCaseInsensitiveContains(searchText) ||
                lesson.subject.localizedCaseInsensitiveContains(searchText) ||
                lesson.group.localizedCaseInsensitiveContains(searchText)
            }
        }

        return lessons
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
            
            // Filters
            filterSection
            
            Divider()
            
            // Content
            if isLoadingStats {
                ProgressView("Loading lesson statistics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredLessons.isEmpty {
                emptyState
            } else {
                lessonList
            }
        }
        .sheet(item: $selectedLesson) { lesson in
            LessonProgressView(lesson: lesson) {
                selectedLesson = nil
            }
        }
        .task {
            await loadAllStats()
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CDLesson Progress")
                    .font(AppTheme.ScaledFont.titleLarge)
                
                Text("\(filteredLessons.count) \(filteredLessons.count == 1 ? "lesson" : "lessons")")
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Filters
    
    private var filterSection: some View {
        VStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search lessons...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
            )
            
            // Subject filter
            if !subjects.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            selectedSubject = nil
                        } label: {
                            Text("All")
                                .font(AppTheme.ScaledFont.bodySemibold)
                                .foregroundStyle(selectedSubject == nil ? .white : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedSubject == nil ? Color.accentColor : Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                                )
                        }
                        .buttonStyle(.plain)
                        
                        ForEach(subjects, id: \.self) { subject in
                            Button {
                                selectedSubject = subject
                            } label: {
                                Text(subject)
                                    .font(AppTheme.ScaledFont.bodySemibold)
                                    .foregroundStyle(selectedSubject == subject ? .white : .primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(
                                                selectedSubject == subject
                                                    ? Color.accentColor
                                                    : Color.primary.opacity(UIConstants.OpacityConstants.subtle)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
    
    // MARK: - CDLesson List
    
    private var lessonList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredLessons) { lesson in
                    lessonRow(lesson)
                }
            }
            .padding(24)
        }
    }
    
    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func lessonRow(_ lesson: CDLesson) -> some View {
        Button {
            selectedLesson = lesson
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(UIConstants.OpacityConstants.accent))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "book.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.indigo)
                }
                
                // CDLesson info
                VStack(alignment: .leading, spacing: 6) {
                    Text(lesson.name)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if !lesson.subject.isEmpty {
                            Text(lesson.subject)
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if !lesson.group.isEmpty {
                            if !lesson.subject.isEmpty {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(lesson.group)
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Stats preview
                if let id = lesson.id, let stats = lessonStats[id] {
                    statsPreview(stats)
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func statsPreview(_ stats: LessonStats) -> some View {
        HStack(spacing: 16) {
            // Presentations
            statBadge(
                icon: "calendar.badge.checkmark",
                value: "\(stats.presentedCount)",
                color: .green
            )
            
            // Work completion
            if stats.totalWorkItems > 0 {
                statBadge(
                    icon: "checkmark.circle",
                    value: "\(Int(stats.workCompletionRate * 100))%",
                    color: .blue
                )
            }
            
            // Active work
            if stats.activeWorkItems > 0 {
                statBadge(
                    icon: "circle.dashed",
                    value: "\(stats.activeWorkItems)",
                    color: .orange
                )
            }
        }
    }
    
    @ViewBuilder
    private func statBadge(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(value)
                .font(AppTheme.ScaledFont.captionSemibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(UIConstants.OpacityConstants.medium))
        )
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: 6) {
                Text("No Lessons Found")
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(.secondary)
                
                Text(
                    searchText.isEmpty
                        ? "Create your first lesson to see progress"
                        : "Try adjusting your search or filters"
                )
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Data Loading
    
    private func loadAllStats() async {
        var statsDict: [UUID: LessonStats] = [:]
        
        for lesson in allLessons {
            guard let lessonID = lesson.id else { continue }
            let stats = lesson.getLessonStats(from: viewContext)
            statsDict[lessonID] = stats
        }
        
        await MainActor.run {
            lessonStats = statsDict
            isLoadingStats = false
        }
    }
}

#Preview("CDLesson Progress List") {
    LessonProgressListView()
        .previewEnvironment()
}
