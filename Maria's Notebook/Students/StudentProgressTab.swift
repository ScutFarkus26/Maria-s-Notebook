// swiftlint:disable file_length
// StudentProgressTab.swift
// Progress tab showing student's active projects and track enrollments with detailed cards

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// swiftlint:disable:next type_body_length
struct StudentProgressTab: View {
    let student: Student

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StudentProgressTabViewModel()

    // MARK: - State
    @State private var selectedEnrollment: StudentTrackEnrollment?
    @State private var selectedProject: Project?
    @State private var selectedReport: WorkModel?
    @State private var filterSheet: FilterSheet?

    // MARK: - Filter Sheet State
    enum FilterSheet: Identifiable {
        case presentations(StudentTrackEnrollment, Track)
        case work(StudentTrackEnrollment, Track)
        case notes(StudentTrackEnrollment, Track)

        var id: String {
            switch self {
            case .presentations(let enrollment, _):
                return "presentations_\(enrollment.id.uuidString)"
            case .work(let enrollment, _):
                return "work_\(enrollment.id.uuidString)"
            case .notes(let enrollment, _):
                return "notes_\(enrollment.id.uuidString)"
            }
        }
    }
    
    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 0. AI-Powered Insights Section
                NavigationLink(destination: StudentInsightsView(student: student)) {
                    HStack(spacing: 16) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(UIConstants.CornerRadius.large)

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                            Text("Development Insights")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Text("AI-powered analysis of recent progress")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(AppTheme.Spacing.medium)
                    #if os(iOS)
                    .background(Color(.systemBackground))
                    #else
                    .background(Color(NSColor.controlBackgroundColor))
                    #endif
                    .cornerRadius(UIConstants.CornerRadius.large)
                    .shadow(color: .purple.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.Spacing.xsmall)
                
                // 1. Projects Section
                if !viewModel.activeProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Active Projects", systemImage: "book.closed.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Spacing.xsmall)

                        ForEach(viewModel.activeProjects) { project in
                            projectRow(project)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedProject = project
                                }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.xsmall)
                }

                // 2. Reports Section
                if !viewModel.activeReports.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Active Reports", systemImage: "doc.text.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Spacing.xsmall)

                        ForEach(viewModel.activeReports) { report in
                            reportCard(report: report)
                                .padding(.horizontal, AppTheme.Spacing.xsmall)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedReport = report
                                }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.xsmall)
                }

                // 3. Tracks Section with detailed cards
                if viewModel.activeEnrollments.isEmpty {
                    if viewModel.activeProjects.isEmpty && viewModel.activeReports.isEmpty {
                        emptyStateView
                            .padding(.top, 60)
                    }
                } else {
                    ForEach(viewModel.activeEnrollments) { enrollment in
                        if let track = viewModel.tracksByID[enrollment.trackID] {
                            enrollmentCard(enrollment: enrollment, track: track)
                                .padding(.horizontal, AppTheme.Spacing.xsmall)
                                .onTapGesture {
                                    selectedEnrollment = enrollment
                                }
                        }
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.medium)
        }
        .onAppear {
            viewModel.configure(for: student, context: modelContext)
        }
        // Sheets
        .sheet(item: $selectedEnrollment) { enrollment in
            if let track = viewModel.tracksByID[enrollment.trackID] {
                StudentTrackDetailView(enrollment: enrollment, track: track)
                    .studentDetailSheetSizing()
            }
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(club: project)
                .studentDetailSheetSizing()
        }
        .sheet(item: $selectedReport) { report in
            WorkDetailView(workID: report.id) {
                selectedReport = nil
            }
            .studentDetailSheetSizing()
        }
        .sheet(item: $filterSheet) { sheet in
            TrackFilteredListSheet(
                sheet: sheet,
                student: student,
                onDismiss: { filterSheet = nil }
            )
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Active Work", systemImage: "list.clipboard")
                .foregroundStyle(.secondary)
        } description: {
            Text("No active projects or track enrollments.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Project Row
    private func projectRow(_ project: Project) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.compact) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.color(forSubject: "Reading").opacity(UIConstants.OpacityConstants.faint))
                    .frame(width: 44, height: 44)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.color(forSubject: "Reading"))
            }
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Text(project.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if let book = project.bookTitle, !book.isEmpty {
                    Text(book)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(AppTheme.Spacing.compact)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }
    
    // MARK: - Enrollment Card
    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func enrollmentCard(enrollment: StudentTrackEnrollment, track: Track) -> some View {
        let stats = viewModel.trackStats(for: enrollment, track: track)
        let progress = viewModel.trackProgress(for: track)
        let trackColor = viewModel.trackColor(for: track.title)

        ProgressCardContainer(color: trackColor, isActive: enrollment.isActive) {
            VStack(alignment: .leading, spacing: 16) {
                ProgressCardHeader(
                    iconName: "list.bullet.rectangle",
                    color: trackColor,
                    title: track.title,
                    subtitle: enrollment.startedAt.map {
                        "Started \($0.formatted(.relative(presentation: .named)))"
                    } ?? "Enrolled \(enrollment.createdAt.formatted(.relative(presentation: .named)))",
                    isComplete: progress.isComplete && progress.totalSteps > 0,
                    isActive: enrollment.isActive
                )

                Divider().padding(.vertical, AppTheme.Spacing.xsmall)

                if progress.totalSteps > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressStatsSection(
                            completed: progress.proficientCount,
                            total: progress.totalSteps,
                            color: trackColor, completionLabel: ""
                        )
                        StepDotsVisualization(
                            steps: progress.trackSteps,
                            completedStepIDs: progress.completedStepIDs,
                            color: trackColor
                        )
                    }
                    .padding(.bottom, AppTheme.Spacing.xsmall)
                }

                if let lesson = progress.currentLesson, progress.totalSteps > 0 {
                    Divider().padding(.vertical, AppTheme.Spacing.xsmall)
                    NextItemBanner(
                        iconName: "book.fill", label: "Next Lesson",
                        title: lesson.name.isEmpty ? "Untitled Lesson" : lesson.name,
                        subtitle: nil, color: trackColor
                    )
                } else if progress.isComplete && progress.totalSteps > 0 {
                    Divider().padding(.vertical, AppTheme.Spacing.xsmall)
                    CompletionTrophyBanner(message: "All lessons mastered!")
                }

                if stats.totalActivity > 0 {
                    Divider().padding(.vertical, AppTheme.Spacing.xsmall)
                    VStack(alignment: .leading, spacing: 12) {
                        ActivityStatsRow(totalActivity: stats.totalActivity, color: trackColor)
                        HStack(spacing: 12) {
                            Button { filterSheet = .presentations(enrollment, track) } label: {
                                ProgressStatBadge(
                                    count: stats.presentationCount,
                                    label: "Presentations",
                                    icon: "person.2.fill", color: .orange
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(stats.presentationCount == 0)

                            Button { filterSheet = .work(enrollment, track) } label: {
                                ProgressStatBadge(
                                    count: stats.workCount, label: "Work",
                                    icon: "briefcase.fill", color: .blue
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(stats.workCount == 0)

                            Button { filterSheet = .notes(enrollment, track) } label: {
                                ProgressStatBadge(
                                    count: stats.noteCount, label: "Notes",
                                    icon: "note.text", color: .yellow
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(stats.noteCount == 0)
                        }
                        if let date = stats.lastActivityDate { LastActivityRow(lastActivityDate: date) }
                    }
                } else if progress.totalSteps == 0 {
                    EmptyStateBanner(iconName: "hourglass", message: "No activity recorded yet")
                }

                let notesPreview = enrollment.latestUnifiedNoteText
                if !notesPreview.trimmed().isEmpty {
                    Divider().padding(.vertical, AppTheme.Spacing.xsmall)
                    NotesPreviewSection(notes: notesPreview, color: trackColor)
                }

                // View Class Progress link
                let trackParts = track.title.components(separatedBy: " — ")
                if trackParts.count == 2 {
                    Divider().padding(.vertical, AppTheme.Spacing.xsmall)
                    Button {
                        let subject = trackParts[0].trimmingCharacters(in: .whitespaces)
                        let group = trackParts[1].trimmingCharacters(in: .whitespaces)
                        AppRouter.shared.navigateToChecklist(subject: subject, group: group)
                    } label: {
                        Label("View Class Progress", systemImage: "checklist")
                            .font(.caption)
                            .foregroundStyle(trackColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            viewModel.autoCompleteTrackIfNeeded(
                enrollment: enrollment, progress: progress, context: modelContext
            )
        }
    }

    // MARK: - Report Card
    @ViewBuilder
    private func reportCard(report: WorkModel) -> some View {
        let progress = report.stepProgress
        let orderedSteps = report.orderedSteps
        let isComplete = progress.completed == progress.total && progress.total > 0

        ProgressCardContainer(color: .green, isActive: true) {
            VStack(alignment: .leading, spacing: 16) {
                ProgressCardHeader(
                    iconName: "doc.text.fill",
                    color: .green,
                    title: viewModel.reportTitle(for: report),
                    subtitle: "Assigned \(report.assignedAt.formatted(.relative(presentation: .named)))",
                    isComplete: isComplete,
                    isActive: false
                )

                Divider().padding(.vertical, AppTheme.Spacing.xsmall)

                if progress.total > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressStatsSection(
                            completed: progress.completed, total: progress.total,
                            color: .green, completionLabel: "steps"
                        )
                        StepDotsVisualization(
                            steps: orderedSteps,
                            completedStepIDs: Set(
                                orderedSteps.filter { $0.completedAt != nil }
                                    .map { $0.id.uuidString }
                            ),
                            color: .green,
                            maxSteps: 15
                        )
                    }
                    .padding(.bottom, AppTheme.Spacing.xsmall)
                }

                if let step = orderedSteps.first(where: { $0.completedAt == nil }), progress.total > 0 {
                    Divider().padding(.vertical, AppTheme.Spacing.xsmall)
                    NextItemBanner(
                        iconName: "arrow.right.circle.fill",
                        label: "Next Step",
                        title: step.title.isEmpty ? "Step \(step.orderIndex + 1)" : step.title,
                        subtitle: step.instructions.isEmpty ? nil : step.instructions,
                        color: .green
                    )
                } else if isComplete && progress.total > 0 {
                    Divider().padding(.vertical, AppTheme.Spacing.xsmall)
                    CompletionTrophyBanner(message: "All steps complete!")
                } else if progress.total == 0 {
                    EmptyStateBanner(iconName: "plus.circle", message: "No steps added yet")
                }
            }
        }
    }
}

// MARK: - Track Filtered List Sheet Wrapper
/// Wrapper view that fetches its own data for TrackFilteredListView
private struct TrackFilteredListSheet: View {
    let sheet: StudentProgressTab.FilterSheet
    let student: Student
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let params = extractParams()
        let (enrollment, track, filterType) = (params.enrollment, params.track, params.filterType)

        // Fetch data on-demand
        let allLessonAssignments = modelContext.safeFetch(FetchDescriptor<LessonAssignment>(
            sortBy: [SortDescriptor(\.presentedAt, order: .reverse)]
        ))
        let allWorkModels = modelContext.safeFetch(FetchDescriptor<WorkModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        let allNotes = modelContext.safeFetch(FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
        let allLessons = modelContext.safeFetch(FetchDescriptor<Lesson>(
            sortBy: [SortDescriptor(\.name)]
        ))

        TrackFilteredListView(
            enrollment: enrollment,
            track: track,
            filterType: filterType,
            allLessonAssignments: allLessonAssignments,
            allWorkModels: allWorkModels,
            allNotes: allNotes,
            allLessons: allLessons,
            onDismiss: onDismiss
        )
        .studentDetailSheetSizing()
    }

    private struct SheetParams {
        let enrollment: StudentTrackEnrollment
        let track: Track
        let filterType: TrackFilterType
    }

    private func extractParams() -> SheetParams {
        switch sheet {
        case .presentations(let enrollment, let track):
            return SheetParams(enrollment: enrollment, track: track, filterType: .presentations)
        case .work(let enrollment, let track):
            return SheetParams(enrollment: enrollment, track: track, filterType: .work)
        case .notes(let enrollment, let track):
            return SheetParams(enrollment: enrollment, track: track, filterType: .notes)
        }
    }
}
