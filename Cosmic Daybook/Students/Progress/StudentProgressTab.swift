// swiftlint:disable file_length
// StudentProgressTab.swift
// Progress tab showing student's active projects, reports and the lesson
// sequences she is in the middle of, as detailed cards

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
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var viewModel = StudentProgressTabViewModel()

    // MARK: - State
    @State private var selectedStanding: SequenceStanding?
    @State private var selectedProject: CDProject?
    @State private var selectedReport: CDWorkModel?
    @State private var selectedFollowUpAssignment: CDLessonAssignment?
    @State private var filterSheet: FilterSheet?

    // MARK: - Filter Sheet State
    enum FilterSheet: Identifiable {
        case presentations(SequenceStanding)
        case work(SequenceStanding)
        case notes(SequenceStanding)

        var id: String {
            switch self {
            case .presentations(let standing):
                return "presentations_\(standing.id)"
            case .work(let standing):
                return "work_\(standing.id)"
            case .notes(let standing):
                return "notes_\(standing.id)"
            }
        }
    }
    
    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let studentID = student.id {
                    FollowingPresentationsView(
                        style: .student,
                        studentID: studentID,
                        onOpen: openFollowingPresentation
                    )
                }

                if !viewModel.activeProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Active Projects", systemImage: "book.closed.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Spacing.xsmall)

                        ForEach(viewModel.activeProjects) { project in
                            Button {
                                selectedProject = project
                            } label: {
                                projectRow(project)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens project details")
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
                            Button {
                                selectedReport = report
                            } label: {
                                reportCard(report: report)
                            }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens report details")
                                .padding(.horizontal, AppTheme.Spacing.xsmall)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.xsmall)
                }

                // 3. Sequences in progress, as detailed cards
                if viewModel.standings.isEmpty {
                    if viewModel.activeProjects.isEmpty && viewModel.activeReports.isEmpty {
                        emptyStateView
                            .padding(.top, 60)
                    }
                } else {
                    ForEach(viewModel.standings) { standing in
                        sequenceCard(standing)
                            .padding(.horizontal, AppTheme.Spacing.xsmall)
                            .onTapGesture {
                                selectedStanding = standing
                            }
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.medium)
        }
        // Edits elsewhere (a lesson given, work closed, a mark) used to leave
        // this tab stale until it was opened again.
        .onPresentationDataChangeWhenVisible(
            of: ["LessonAssignment", "WorkModel", "LessonPresentation"],
            in: viewContext,
            catchUpOnAppear: false
        ) {
            viewModel.loadData(for: student, context: viewContext)
        }
        .onAppear {
            viewModel.configure(for: student, context: viewContext)
        }
        // Sheets
        .sheet(item: $selectedStanding) { standing in
            StudentTrackDetailView(student: student, standing: standing)
                .studentDetailSheetSizing()
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
        #if os(iOS)
        .sheet(item: $selectedFollowUpAssignment) { assignment in
            PresentationDetailView(lessonAssignment: assignment) {
                selectedFollowUpAssignment = nil
            }
            .studentDetailSheetSizing()
        }
        #endif
        .sheet(item: $filterSheet) { sheet in
            TrackFilteredListSheet(
                sheet: sheet,
                student: student,
                onDismiss: { filterSheet = nil }
            )
        }
    }

    private func openFollowingPresentation(_ assignment: CDLessonAssignment) {
        #if os(macOS)
        guard let id = assignment.id else { return }
        openWindow(id: "PresentationDetailWindow", value: id)
        #else
        selectedFollowUpAssignment = assignment
        #endif
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Active Work", systemImage: "list.clipboard")
                .foregroundStyle(.secondary)
        } description: {
            Text("No active projects or lessons in progress.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - CDProject Row
    private func projectRow(_ project: CDProject) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.compact) {
            ZStack {
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control, style: .continuous)
                    .fill(AppColors.color(forArea: "Reading").opacity(UIConstants.OpacityConstants.faint))
                    .frame(width: 44, height: 44)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.color(forArea: "Reading"))
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
        .surface(
            UIConstants.CornerRadius.large,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.veryFaint),
            style: .continuous
        )
    }
    
    // MARK: - Sequence Card
    @ViewBuilder
    private func sequenceCard(_ standing: SequenceStanding) -> some View {
        let stats = viewModel.stats(for: standing)
        let cardColor: Color = viewModel.trackColor(for: standing.title)

        ProgressCardContainer(color: cardColor, isActive: true) {
            VStack(alignment: .leading, spacing: 16) {
                sequenceCardHeader(standing, color: cardColor)
                sequenceCardProgress(standing, color: cardColor)
                sequenceCardNextItem(standing, color: cardColor)
                sequenceCardActivity(standing, stats: stats, color: cardColor)
                sequenceCardNotes(stats, color: cardColor)
                sequenceCardClassLink(standing, color: cardColor)
            }
        }
    }

    @ViewBuilder
    private func sequenceCardHeader(_ standing: SequenceStanding, color: Color) -> some View {
        let subtitle: String = standing.firstGivenAt.map {
            "Started \($0.formatted(.relative(presentation: .named)))"
        } ?? "Not started yet"

        ProgressCardHeader(
            iconName: "list.bullet.rectangle",
            color: color,
            title: standing.title,
            subtitle: subtitle,
            isComplete: standing.isFinished,
            isActive: !standing.isFinished
        )

        Divider().padding(.vertical, AppTheme.Spacing.xsmall)
    }

    @ViewBuilder
    private func sequenceCardProgress(_ standing: SequenceStanding, color: Color) -> some View {
        if standing.total > 0 {
            VStack(alignment: .leading, spacing: 12) {
                ProgressStatsSection(
                    completed: standing.masteredCount,
                    total: standing.total,
                    color: color, completionLabel: ""
                )
                StepDotsVisualization(
                    steps: standing.lessons,
                    completedStepIDs: Set(standing.lessons.filter { standing.isMastered($0) }.map(\.stepID)),
                    color: color
                )
            }
            .padding(.bottom, AppTheme.Spacing.xsmall)
        }
    }

    @ViewBuilder
    private func sequenceCardNextItem(_ standing: SequenceStanding, color: Color) -> some View {
        if let lesson = viewModel.nextLessonByStanding[standing.id] {
            Divider().padding(.vertical, AppTheme.Spacing.xsmall)
            NextItemBanner(
                iconName: "book.fill", label: "Next Lesson",
                title: lesson.name.isEmpty ? "Untitled Lesson" : lesson.name,
                subtitle: nil, color: color
            )
        } else if standing.isFinished {
            Divider().padding(.vertical, AppTheme.Spacing.xsmall)
            CompletionTrophyBanner(message: "All lessons mastered!")
        }
    }

    @ViewBuilder
    private func sequenceCardActivity(
        _ standing: SequenceStanding,
        stats: StudentProgressTabViewModel.SequenceStats,
        color: Color
    ) -> some View {
        if stats.totalActivity > 0 {
            Divider().padding(.vertical, AppTheme.Spacing.xsmall)
            VStack(alignment: .leading, spacing: 12) {
                ActivityStatsRow(totalActivity: stats.totalActivity, color: color)
                activityFilterButtons(standing, stats: stats)
                if let date = stats.lastActivityDate { LastActivityRow(lastActivityDate: date) }
            }
        } else if standing.total == 0 {
            EmptyStateBanner(iconName: "hourglass", message: "No activity recorded yet")
        }
    }

    private func activityFilterButtons(
        _ standing: SequenceStanding,
        stats: StudentProgressTabViewModel.SequenceStats
    ) -> some View {
        HStack(spacing: 12) {
            Button { filterSheet = .presentations(standing) } label: {
                ProgressStatBadge(
                    count: stats.presentationCount,
                    label: "Presentations",
                    icon: "person.2.fill",
                    color: .orange
                )
            }
            .buttonStyle(.plain)
            .disabled(stats.presentationCount == 0)

            Button { filterSheet = .work(standing) } label: {
                ProgressStatBadge(count: stats.workCount, label: "Work", icon: "briefcase.fill", color: .blue)
            }
            .buttonStyle(.plain)
            .disabled(stats.workCount == 0)

            Button { filterSheet = .notes(standing) } label: {
                ProgressStatBadge(count: stats.noteCount, label: "Notes", icon: "note.text", color: .yellow)
            }
            .buttonStyle(.plain)
            .disabled(stats.noteCount == 0)
        }
    }

    @ViewBuilder
    private func sequenceCardNotes(_ stats: StudentProgressTabViewModel.SequenceStats, color: Color) -> some View {
        let notesPreview: String = CDNote.latestBody(in: stats.notes)
        if !notesPreview.trimmed().isEmpty {
            Divider().padding(.vertical, AppTheme.Spacing.xsmall)
            NotesPreviewSection(notes: notesPreview, color: color)
        }
    }

    @ViewBuilder
    private func sequenceCardClassLink(_ standing: SequenceStanding, color: Color) -> some View {
        Divider().padding(.vertical, AppTheme.Spacing.xsmall)
        Button {
            AppRouter.shared.navigateToChecklist(area: standing.area, sequence: standing.sequence)
        } label: {
            Label("View Class Progress", systemImage: "checklist")
                .font(.caption)
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Report Card

    /// "Writing · assigned 3 weeks ago": the report's stage first (2026-10-30).
    private func reportSubtitle(_ report: CDWorkModel) -> String {
        let assigned = (report.assignedAt ?? Date()).formatted(.relative(presentation: .named))
        guard let stage = ReportStages.stageName(of: report) else { return "Assigned \(assigned)" }
        return "\(stage) · assigned \(assigned)"
    }

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
                    subtitle: reportSubtitle(report),
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

// MARK: - Filtered List Sheet Wrapper
/// Wrapper view that fetches its own data for TrackFilteredListView
private struct TrackFilteredListSheet: View {
    let sheet: StudentProgressTab.FilterSheet
    let student: CDStudent
    let onDismiss: () -> Void

    @Environment(\.managedObjectContext) private var viewContext

    @State private var data: TrackFilteredListData?

    var body: some View {
        let params = extractParams()

        Group {
            if let data {
                TrackFilteredListView(
                    standing: params.standing,
                    filterType: params.filterType,
                    data: data,
                    onDismiss: onDismiss
                )
            } else {
                ProgressView()
            }
        }
        .task {
            // Fetch once, scoped to the child and this sequence's lessons,
            // instead of re-running whole-table fetches on every body evaluation.
            data = TrackFilteredListLoader.load(
                studentID: student.id?.uuidString ?? "",
                standing: params.standing,
                filterType: params.filterType,
                context: viewContext
            )
        }
        .studentDetailSheetSizing()
    }

    private struct SheetParams {
        let standing: SequenceStanding
        let filterType: TrackFilterType
    }

    private func extractParams() -> SheetParams {
        switch sheet {
        case .presentations(let standing):
            return SheetParams(standing: standing, filterType: .presentations)
        case .work(let standing):
            return SheetParams(standing: standing, filterType: .work)
        case .notes(let standing):
            return SheetParams(standing: standing, filterType: .notes)
        }
    }
}
