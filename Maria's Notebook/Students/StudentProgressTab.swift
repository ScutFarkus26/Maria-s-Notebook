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
    @StateObject private var viewModel = StudentProgressTabViewModel()

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
    private func enrollmentCard(
        enrollment: StudentTrackEnrollment,
        track: Track
    ) -> some View {
        // Get stats and progress from viewModel
        let stats = viewModel.trackStats(for: enrollment, track: track)
        let progress = viewModel.trackProgress(for: track)

        let presentationCount = stats.presentationCount
        let workCount = stats.workCount
        let noteCount = stats.noteCount
        let totalActivity = stats.totalActivity
        let lastActivityDate = stats.lastActivityDate

        let trackColor = viewModel.trackColor(for: track.title)
        let hasNotes = enrollment.notes?.trimmed().isEmpty == false

        let trackSteps = progress.trackSteps
        let completedStepIDs = progress.completedStepIDs
        let masteredCount = progress.masteredCount
        let totalSteps = progress.totalSteps
        let progressPercent = progress.progressPercent
        let isComplete = progress.isComplete
        let currentLesson = progress.currentLesson

        VStack(alignment: .leading, spacing: 16) {
            // Header with track icon and title
            HStack(spacing: 12) {
                // Track icon/indicator
                ZStack {
                    Circle()
                        .fill(trackColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(trackColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    // Started date or enrollment date
                    if let startedAt = enrollment.startedAt {
                        Text("Started \(startedAt, style: .relative)")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Enrolled \(enrollment.createdAt, style: .relative)")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Active badge
                if enrollment.isActive {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else if isComplete && totalSteps > 0 {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Progress visualization
            if totalSteps > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    // Progress stats
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(masteredCount)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(trackColor)
                        
                        Text("/ \(totalSteps)")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(progressPercent * 100))%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(progressPercent >= 1.0 ? .green : .primary)
                    }
                    
                    // Animated progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 12)
                            
                            // Progress fill with animated width
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: isComplete
                                            ? [Color.green, Color.green.opacity(0.8)]
                                            : [trackColor, trackColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: {
                                        let w = geometry.size.width
                                        let val = w * progressPercent
                                        // Guard against NaN or Infinity
                                        return (w.isFinite && val.isFinite && val > 0) ? min(w, val) : 0
                                    }(),
                                    height: 12
                                )
                            
                            // Glow effect for completed tracks
                            if isComplete && progressPercent >= 1.0 {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.green.opacity(0.2),
                                                Color.green.opacity(0.1),
                                                Color.green.opacity(0.2)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: geometry.size.width,
                                        height: 12
                                    )
                                    .blur(radius: 2)
                            }
                        }
                    }
                    .frame(height: 12)
                    
                    // Step dots visualization (if 30 or fewer steps)
                    if totalSteps > 0 && totalSteps <= 30 {
                        HStack(spacing: 6) {
                            ForEach(0..<totalSteps, id: \.self) { index in
                                let step = trackSteps[safe: index]
                                let isCompleted = step.map { completedStepIDs.contains($0.id.uuidString) } ?? false
                                
                                Circle()
                                    .fill(isCompleted ? trackColor : Color.secondary.opacity(0.2))
                                    .frame(width: 8, height: 8)
                                    .overlay {
                                        if isCompleted {
                                            Circle()
                                                .stroke(trackColor.opacity(0.3), lineWidth: 2)
                                                .scaleEffect(1.3)
                                        }
                                    }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom, 4)
            }
            
            // Current/Next lesson
            if let currentLesson = currentLesson, totalSteps > 0 {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(trackColor.opacity(0.7))
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next Lesson")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Text(currentLesson.name.isEmpty ? "Untitled Lesson" : currentLesson.name)
                            .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(trackColor.opacity(0.08))
                )
            } else if isComplete && totalSteps > 0 {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("All lessons mastered!")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.1))
                )
            }
            
            // Stats section
            if totalActivity > 0 {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(totalActivity)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(trackColor)
                        
                        Text("total activities")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                    
                    // Stats badges (clickable)
                    HStack(spacing: 12) {
                        Button {
                            filterSheet = .presentations(enrollment, track)
                        } label: {
                            statBadge(
                                count: presentationCount,
                                label: "Presentations",
                                icon: "person.2.fill",
                                color: .orange
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(presentationCount == 0)
                        
                        Button {
                            filterSheet = .work(enrollment, track)
                        } label: {
                            statBadge(
                                count: workCount,
                                label: "Work",
                                icon: "briefcase.fill",
                                color: .blue
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(workCount == 0)
                        
                        Button {
                            filterSheet = .notes(enrollment, track)
                        } label: {
                            statBadge(
                                count: noteCount,
                                label: "Notes",
                                icon: "note.text",
                                color: .yellow
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(noteCount == 0)
                    }
                    
                    // Last activity
                    if let lastActivityDate = lastActivityDate {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            
                            Text("Last activity \(lastActivityDate, style: .relative)")
                                .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            } else if totalSteps == 0 {
                // No steps defined yet
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary.opacity(0.7))
                    
                    Text("No activity recorded yet")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
            
            // Enrollment notes preview
            if hasNotes, let notes = enrollment.notes {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 14))
                        .foregroundStyle(trackColor.opacity(0.7))
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notes")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Text(notes)
                            .font(.system(size: AppTheme.FontSize.callout, weight: .regular, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(trackColor.opacity(0.08))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(viewModel.cardBackgroundColor)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            trackColor.opacity(enrollment.isActive ? 0.3 : 0.15),
                            trackColor.opacity(enrollment.isActive ? 0.15 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: enrollment.isActive ? 2 : 1
                )
        )
        .onAppear {
            viewModel.autoCompleteTrackIfNeeded(enrollment: enrollment, progress: progress, context: modelContext)
        }
    }
    
    private func statBadge(count: Int, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)

            Text("\(count)")
                .font(.system(size: AppTheme.FontSize.caption, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(label)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Report Card
    @ViewBuilder
    private func reportCard(report: WorkModel) -> some View {
        let reportColor = Color.green
        let progress = report.stepProgress
        let totalSteps = progress.total
        let completedSteps = progress.completed
        let progressPercent = totalSteps > 0 ? Double(completedSteps) / Double(totalSteps) : 0.0
        let isComplete = completedSteps == totalSteps && totalSteps > 0

        // Get report title from viewModel
        let reportTitle = viewModel.reportTitle(for: report)

        // Find the current/next step
        let orderedSteps = report.orderedSteps
        let currentStep = orderedSteps.first { $0.completedAt == nil }

        VStack(alignment: .leading, spacing: 16) {
            // Header with report icon and title
            HStack(spacing: 12) {
                // Report icon/indicator
                ZStack {
                    Circle()
                        .fill(reportColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(reportColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(reportTitle)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Assigned \(report.assignedAt, style: .relative)")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status badge
                if isComplete {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)

                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: "circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Progress visualization
            if totalSteps > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    // Progress stats
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(completedSteps)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(reportColor)

                        Text("/ \(totalSteps) steps")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(Int(progressPercent * 100))%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(progressPercent >= 1.0 ? .green : .primary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 12)

                            // Progress fill
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: isComplete
                                            ? [Color.green, Color.green.opacity(0.8)]
                                            : [reportColor, reportColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: {
                                        let w = geometry.size.width
                                        let val = w * progressPercent
                                        return (w.isFinite && val.isFinite && val > 0) ? min(w, val) : 0
                                    }(),
                                    height: 12
                                )
                        }
                    }
                    .frame(height: 12)

                    // Step dots visualization (if 15 or fewer steps)
                    if totalSteps > 0 && totalSteps <= 15 {
                        HStack(spacing: 6) {
                            ForEach(0..<totalSteps, id: \.self) { index in
                                let step = orderedSteps[safe: index]
                                let isStepCompleted = step?.completedAt != nil

                                Circle()
                                    .fill(isStepCompleted ? reportColor : Color.secondary.opacity(0.2))
                                    .frame(width: 10, height: 10)
                                    .overlay {
                                        if isStepCompleted {
                                            Circle()
                                                .stroke(reportColor.opacity(0.3), lineWidth: 2)
                                                .scaleEffect(1.3)
                                        }
                                    }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom, 4)
            }

            // Current/Next step
            if let currentStep = currentStep, totalSteps > 0 {
                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(reportColor.opacity(0.7))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next Step")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(currentStep.title.isEmpty ? "Step \(currentStep.orderIndex + 1)" : currentStep.title)
                            .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        if !currentStep.instructions.isEmpty {
                            Text(currentStep.instructions)
                                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(reportColor.opacity(0.08))
                )
            } else if isComplete && totalSteps > 0 {
                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("All steps complete!")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.1))
                )
            } else if totalSteps == 0 {
                // No steps defined yet
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary.opacity(0.7))

                    Text("No steps added yet")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(viewModel.cardBackgroundColor)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            reportColor.opacity(0.3),
                            reportColor.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
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
