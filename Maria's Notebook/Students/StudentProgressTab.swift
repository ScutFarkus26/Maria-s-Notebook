// swiftlint:disable file_length
// StudentProgressTab.swift
// Progress tab showing student's active projects and track enrollments with detailed cards

import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// swiftlint:disable:next type_body_length
struct StudentProgressTab: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = StudentProgressTabViewModel()

    // MARK: - State
    @State private var selectedEnrollment: CDStudentTrackEnrollmentEntity?
    @State private var selectedProject: CDProject?
    @State private var selectedReport: CDWorkModel?
    @State private var filterSheet: FilterSheet?

    // MARK: - Filter Sheet State
    enum FilterSheet: Identifiable {
        case presentations(CDStudentTrackEnrollmentEntity, CDTrackEntity)
        case work(CDStudentTrackEnrollmentEntity, CDTrackEntity)
        case notes(CDStudentTrackEnrollmentEntity, CDTrackEntity)

        var id: String {
            switch self {
            case .presentations(let enrollment, _):
                return "presentations_\(enrollment.id?.uuidString ?? "")"
            case .work(let enrollment, _):
                return "work_\(enrollment.id?.uuidString ?? "")"
            case .notes(let enrollment, _):
                return "notes_\(enrollment.id?.uuidString ?? "")"
            }
        }
    }
    
    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                insightsLink

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
            viewModel.configure(for: student, context: viewContext)
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
            WorkDetailView(workID: report.id ?? UUID()) {
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
    
    // MARK: - Insights Link

    private var insightsLink: some View {
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
            .shadow(color: .purple.opacity(UIConstants.OpacityConstants.moderate), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppTheme.Spacing.xsmall)
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
    
    // MARK: - CDProject Row
    private func projectRow(_ project: CDProject) -> some View {
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
                .foregroundStyle(.secondary.opacity(UIConstants.OpacityConstants.half))
        }
        .padding(AppTheme.Spacing.compact)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }
    
    // MARK: - Enrollment Card
    @ViewBuilder
    private func enrollmentCard(enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity) -> some View {
        let stats = viewModel.trackStats(for: enrollment, track: track)
        let progress = viewModel.trackProgress(for: track)
        let trackColor: Color = viewModel.trackColor(for: track.title)

        ProgressCardContainer(color: trackColor, isActive: enrollment.isActive) {
            VStack(alignment: .leading, spacing: 16) {
                enrollmentCardHeader(enrollment: enrollment, track: track, progress: progress, color: trackColor)
                enrollmentCardProgress(progress: progress, color: trackColor)
                enrollmentCardNextItem(progress: progress, color: trackColor)
                enrollmentCardActivity(enrollment: enrollment, track: track, stats: stats, progress: progress, color: trackColor)
                enrollmentCardNotes(enrollment: enrollment, color: trackColor)
                enrollmentCardClassLink(track: track, color: trackColor)
            }
        }
        .onAppear {
            viewModel.autoCompleteTrackIfNeeded(
                enrollment: enrollment, progress: progress, context: viewContext
            )
        }
    }

    @ViewBuilder
    private func enrollmentCardHeader(enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity, progress: StudentProgressTabViewModel.TrackProgress, color: Color) -> some View {
        let subtitle: String = enrollment.startedAt.map {
            "Started \($0.formatted(.relative(presentation: .named)))"
        } ?? "Enrolled \((enrollment.createdAt ?? Date()).formatted(.relative(presentation: .named)))"

        ProgressCardHeader(
            iconName: "list.bullet.rectangle",
            color: color,
            title: track.title,
            subtitle: subtitle,
            isComplete: progress.isComplete && progress.totalSteps > 0,
            isActive: enrollment.isActive
        )

        Divider().padding(.vertical, AppTheme.Spacing.xsmall)
    }

    @ViewBuilder
    private func enrollmentCardProgress(progress: StudentProgressTabViewModel.TrackProgress, color: Color) -> some View {
        if progress.totalSteps > 0 {
            VStack(alignment: .leading, spacing: 12) {
                ProgressStatsSection(
                    completed: progress.proficientCount,
                    total: progress.totalSteps,
                    color: color, completionLabel: ""
                )
                StepDotsVisualization(
                    steps: progress.trackSteps,
                    completedStepIDs: progress.completedStepIDs,
                    color: color
                )
            }
            .padding(.bottom, AppTheme.Spacing.xsmall)
        }
    }

    @ViewBuilder
    private func enrollmentCardNextItem(progress: StudentProgressTabViewModel.TrackProgress, color: Color) -> some View {
        if let lesson = progress.currentLesson, progress.totalSteps > 0 {
            Divider().padding(.vertical, AppTheme.Spacing.xsmall)
            NextItemBanner(
                iconName: "book.fill", label: "Next Lesson",
                title: lesson.name.isEmpty ? "Untitled Lesson" : lesson.name,
                subtitle: nil, color: color
            )
        } else if progress.isComplete && progress.totalSteps > 0 {
            Divider().padding(.vertical, AppTheme.Spacing.xsmall)
            CompletionTrophyBanner(message: "All lessons mastered!")
        }
    }

    @ViewBuilder
    private func enrollmentCardActivity(enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity, stats: StudentProgressTabViewModel.TrackStats, progress: StudentProgressTabViewModel.TrackProgress, color: Color) -> some View { // swiftlint:disable:this function_parameter_count
        if stats.totalActivity > 0 {
            Divider().padding(.vertical, AppTheme.Spacing.xsmall)
            activityStatsContent(enrollment: enrollment, track: track, stats: stats, color: color)
        } else if progress.totalSteps == 0 {
            EmptyStateBanner(iconName: "hourglass", message: "No activity recorded yet")
        }
    }

    private func activityStatsContent(enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity, stats: StudentProgressTabViewModel.TrackStats, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ActivityStatsRow(totalActivity: stats.totalActivity, color: color)
            activityFilterButtons(enrollment: enrollment, track: track, stats: stats)
            if let date = stats.lastActivityDate { LastActivityRow(lastActivityDate: date) }
        }
    }

    private func activityFilterButtons(enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity, stats: StudentProgressTabViewModel.TrackStats) -> some View {
        HStack(spacing: 12) {
            Button { filterSheet = .presentations(enrollment, track) } label: {
                ProgressStatBadge(count: stats.presentationCount, label: "Presentations", icon: "person.2.fill", color: .orange)
            }
            .buttonStyle(.plain)
            .disabled(stats.presentationCount == 0)

            Button { filterSheet = .work(enrollment, track) } label: {
                ProgressStatBadge(count: stats.workCount, label: "Work", icon: "briefcase.fill", color: .blue)
            }
            .buttonStyle(.plain)
            .disabled(stats.workCount == 0)

            Button { filterSheet = .notes(enrollment, track) } label: {
                ProgressStatBadge(count: stats.noteCount, label: "Notes", icon: "note.text", color: .yellow)
            }
            .buttonStyle(.plain)
            .disabled(stats.noteCount == 0)
        }
    }

    @ViewBuilder
    private func enrollmentCardNotes(enrollment: CDStudentTrackEnrollmentEntity, color: Color) -> some View {
        let notesPreview: String = enrollment.latestUnifiedNoteText
        if !notesPreview.trimmed().isEmpty {
            Divider().padding(.vertical, AppTheme.Spacing.xsmall)
            NotesPreviewSection(notes: notesPreview, color: color)
        }
    }

    @ViewBuilder
    private func enrollmentCardClassLink(track: CDTrackEntity, color: Color) -> some View {
        let trackParts: [String] = track.title.components(separatedBy: " — ")
        if trackParts.count == 2 {
            Divider().padding(.vertical, AppTheme.Spacing.xsmall)
            Button {
                let subject: String = trackParts[0].trimmingCharacters(in: .whitespaces)
                let group: String = trackParts[1].trimmingCharacters(in: .whitespaces)
                AppRouter.shared.navigateToChecklist(subject: subject, group: group)
            } label: {
                Label("View Class Progress", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Report Card
    @ViewBuilder
    private func reportCard(report: CDWorkModel) -> some View {
        let progress = report.stepProgress
        let orderedSteps = report.orderedSteps
        let isComplete = progress.completed == progress.total && progress.total > 0

        ProgressCardContainer(color: .green, isActive: true) {
            VStack(alignment: .leading, spacing: 16) {
                ProgressCardHeader(
                    iconName: "doc.text.fill",
                    color: .green,
                    title: viewModel.reportTitle(for: report),
                    subtitle: "Assigned \((report.assignedAt ?? Date()).formatted(.relative(presentation: .named)))",
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
                                    .compactMap { $0.id?.uuidString }
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

// MARK: - CDTrackEntity Filtered List Sheet Wrapper
/// Wrapper view that fetches its own data for TrackFilteredListView
private struct TrackFilteredListSheet: View {
    let sheet: StudentProgressTab.FilterSheet
    let student: CDStudent
    let onDismiss: () -> Void

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        let params = extractParams()
        let (enrollment, track, filterType) = (params.enrollment, params.track, params.filterType)

        // Fetch data on-demand
        let allLessonAssignments: [CDLessonAssignment] = {
            let r: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
            r.sortDescriptors = [NSSortDescriptor(key: "presentedAt", ascending: false)]
            return viewContext.safeFetch(r)
        }()

        let allWorkModels: [CDWorkModel] = {
            let r: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
            r.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            return viewContext.safeFetch(r)
        }()

        let allNotes: [CDNote] = {
            let r: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
            r.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return viewContext.safeFetch(r)
        }()

        let allLessons: [CDLesson] = {
            let r: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
            r.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            return viewContext.safeFetch(r)
        }()

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
        let enrollment: CDStudentTrackEnrollmentEntity
        let track: CDTrackEntity
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
