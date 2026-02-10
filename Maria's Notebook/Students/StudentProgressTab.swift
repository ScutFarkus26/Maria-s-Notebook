// StudentProgressTab.swift
// Progress tab showing student's active projects and track enrollments with detailed cards

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct StudentProgressTab: View {
    let student: Student

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StudentProgressTabViewModel()

    // MARK: - State
    @State private var selectedEnrollment: StudentTrackEnrollment?
    @State private var selectedProject: Project?
    @State private var selectedReport: WorkModel?
    @State private var filterSheet: FilterSheet? = nil

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
                            .cornerRadius(12)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Development Insights")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("AI-powered analysis of recent progress")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    #if os(iOS)
                    .background(Color(.systemBackground))
                    #else
                    .background(Color(NSColor.controlBackgroundColor))
                    #endif
                    .cornerRadius(12)
                    .shadow(color: .purple.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                
                // 1. Projects Section
                if !viewModel.activeProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Active Projects", systemImage: "book.closed.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(viewModel.activeProjects) { project in
                            projectRow(project)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedProject = project
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // 2. Reports Section
                if !viewModel.activeReports.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Active Reports", systemImage: "doc.text.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(viewModel.activeReports) { report in
                            reportCard(report: report)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedReport = report
                                }
                        }
                    }
                    .padding(.horizontal, 4)
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
                                .padding(.horizontal, 4)
                                .onTapGesture {
                                    selectedEnrollment = enrollment
                                }
                        }
                    }
                }
            }
            .padding(.vertical, 16)
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
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.color(forSubject: "Reading").opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.color(forSubject: "Reading"))
            }
            
            VStack(alignment: .leading, spacing: 4) {
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
    
    // MARK: - Enrollment Card
    @ViewBuilder
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
                    subtitle: enrollment.startedAt.map { "Started \($0.formatted(.relative(presentation: .named)))" } ?? "Enrolled \(enrollment.createdAt.formatted(.relative(presentation: .named)))",
                    isComplete: progress.isComplete && progress.totalSteps > 0,
                    isActive: enrollment.isActive
                )

                Divider().padding(.vertical, 4)

                if progress.totalSteps > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressStatsSection(completed: progress.masteredCount, total: progress.totalSteps, color: trackColor, completionLabel: "")
                        StepDotsVisualization(steps: progress.trackSteps, completedStepIDs: progress.completedStepIDs, color: trackColor)
                    }
                    .padding(.bottom, 4)
                }

                if let lesson = progress.currentLesson, progress.totalSteps > 0 {
                    Divider().padding(.vertical, 4)
                    NextItemBanner(iconName: "book.fill", label: "Next Lesson", title: lesson.name.isEmpty ? "Untitled Lesson" : lesson.name, subtitle: nil, color: trackColor)
                } else if progress.isComplete && progress.totalSteps > 0 {
                    Divider().padding(.vertical, 4)
                    CompletionTrophyBanner(message: "All lessons mastered!")
                }

                if stats.totalActivity > 0 {
                    Divider().padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 12) {
                        ActivityStatsRow(totalActivity: stats.totalActivity, color: trackColor)
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
                        if let date = stats.lastActivityDate { LastActivityRow(lastActivityDate: date) }
                    }
                } else if progress.totalSteps == 0 {
                    EmptyStateBanner(iconName: "hourglass", message: "No activity recorded yet")
                }

                if let notes = enrollment.notes, !notes.trimmed().isEmpty {
                    Divider().padding(.vertical, 4)
                    NotesPreviewSection(notes: notes, color: trackColor)
                }
            }
        }
        .onAppear { viewModel.autoCompleteTrackIfNeeded(enrollment: enrollment, progress: progress, context: modelContext) }
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

                Divider().padding(.vertical, 4)

                if progress.total > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressStatsSection(completed: progress.completed, total: progress.total, color: .green, completionLabel: "steps")
                        StepDotsVisualization(
                            steps: orderedSteps,
                            completedStepIDs: Set(orderedSteps.filter { $0.completedAt != nil }.map { $0.id.uuidString }),
                            color: .green,
                            maxSteps: 15
                        )
                    }
                    .padding(.bottom, 4)
                }

                if let step = orderedSteps.first(where: { $0.completedAt == nil }), progress.total > 0 {
                    Divider().padding(.vertical, 4)
                    NextItemBanner(
                        iconName: "arrow.right.circle.fill",
                        label: "Next Step",
                        title: step.title.isEmpty ? "Step \(step.orderIndex + 1)" : step.title,
                        subtitle: step.instructions.isEmpty ? nil : step.instructions,
                        color: .green
                    )
                } else if isComplete && progress.total > 0 {
                    Divider().padding(.vertical, 4)
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
        let (enrollment, track, filterType) = extractParams()

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

    private func extractParams() -> (StudentTrackEnrollment, Track, TrackFilterType) {
        switch sheet {
        case .presentations(let enrollment, let track):
            return (enrollment, track, .presentations)
        case .work(let enrollment, let track):
            return (enrollment, track, .work)
        case .notes(let enrollment, let track):
            return (enrollment, track, .notes)
        }
    }
}
