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
    
    // MARK: - Queries
    
    // Enrollments
    @Query(sort: [SortDescriptor(\StudentTrackEnrollment.createdAt, order: .reverse)])
    private var allEnrollments: [StudentTrackEnrollment]
    
    // Tracks lookup
    @Query(sort: [SortDescriptor(\Track.title)])
    private var allTracks: [Track]
    
    // Projects
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)])
    private var allProjects: [Project]
    
    // Additional queries for track details
    @Query(sort: [SortDescriptor(\Presentation.presentedAt, order: .reverse)])
    private var allPresentations: [Presentation]
    
    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var allWorkModels: [WorkModel]
    
    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var allNotes: [Note]
    
    @Query(sort: [SortDescriptor(\TrackStep.orderIndex)])
    private var allTrackSteps: [TrackStep]
    
    @Query(sort: [SortDescriptor(\Lesson.name)])
    private var allLessons: [Lesson]
    
    // MARK: - State
    @State private var selectedEnrollment: StudentTrackEnrollment?
    @State private var selectedProject: Project?
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
    
    // MARK: - Computed Properties
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
    
    private var activeEnrollments: [StudentTrackEnrollment] {
        let sid = student.id.uuidString
        return allEnrollments.filter { $0.studentID == sid && $0.isActive }
    }
    
    private var activeProjects: [Project] {
        let sid = student.id.uuidString
        return allProjects.filter { $0.memberStudentIDs.contains(sid) && $0.isActive }
    }
    
    private var tracksByID: [String: Track] {
        Dictionary(uniqueKeysWithValues: allTracks.map { ($0.id.uuidString, $0) })
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Projects Section
                if !activeProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Active Projects", systemImage: "book.closed.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        
                        ForEach(activeProjects) { project in
                            projectRow(project)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedProject = project
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                
                // 2. Tracks Section with detailed cards
                if activeEnrollments.isEmpty {
                    if activeProjects.isEmpty {
                        emptyStateView
                            .padding(.top, 60)
                    }
                } else {
                    ForEach(activeEnrollments) { enrollment in
                        if let track = tracksByID[enrollment.trackID] {
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
        // Sheets
        .sheet(item: $selectedEnrollment) { enrollment in
            if let track = tracksByID[enrollment.trackID] {
                StudentTrackDetailView(enrollment: enrollment, track: track)
                    .studentDetailSheetSizing()
            }
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(club: project)
                .studentDetailSheetSizing()
        }
        .sheet(item: $filterSheet) { sheet in
            switch sheet {
            case .presentations(let enrollment, let track):
                TrackFilteredListView(
                    enrollment: enrollment,
                    track: track,
                    filterType: .presentations,
                    allPresentations: allPresentations,
                    allWorkModels: allWorkModels,
                    allNotes: allNotes,
                    allLessons: allLessons,
                    onDismiss: { filterSheet = nil }
                )
                .studentDetailSheetSizing()
            case .work(let enrollment, let track):
                TrackFilteredListView(
                    enrollment: enrollment,
                    track: track,
                    filterType: .work,
                    allPresentations: allPresentations,
                    allWorkModels: allWorkModels,
                    allNotes: allNotes,
                    allLessons: allLessons,
                    onDismiss: { filterSheet = nil }
                )
                .studentDetailSheetSizing()
            case .notes(let enrollment, let track):
                TrackFilteredListView(
                    enrollment: enrollment,
                    track: track,
                    filterType: .notes,
                    allPresentations: allPresentations,
                    allWorkModels: allWorkModels,
                    allNotes: allNotes,
                    allLessons: allLessons,
                    onDismiss: { filterSheet = nil }
                )
                .studentDetailSheetSizing()
            }
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
        let studentIDString = student.id.uuidString
        let trackIDString = track.id.uuidString
        
        // Get stats for this track enrollment
        let presentations = allPresentations.filter {
            $0.trackID == trackIDString && $0.studentIDs.contains(studentIDString)
        }
        let workModels = allWorkModels.filter {
            $0.trackID == trackIDString && $0.studentID == studentIDString
        }
        let notes = allNotes.filter {
            $0.studentTrackEnrollment?.id == enrollment.id
        }
        
        let presentationCount = presentations.count
        let workCount = workModels.count
        let noteCount = notes.count
        let totalActivity = presentationCount + workCount + noteCount
        
        // Get last activity date
        let lastActivityDate: Date? = {
            var dates: [Date] = []
            dates.append(contentsOf: presentations.map { $0.presentedAt })
            dates.append(contentsOf: workModels.compactMap { $0.completedAt ?? $0.createdAt })
            dates.append(contentsOf: notes.map { $0.updatedAt })
            return dates.max()
        }()
        
        let trackColor = trackColorForTitle(track.title)
        let hasNotes = enrollment.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        
        // Calculate progress based on TrackSteps and Presentations
        let trackSteps = allTrackSteps
            .filter { $0.track?.id == track.id }
            .sorted { $0.orderIndex < $1.orderIndex }
        
        let completedStepIDs = Set(presentations
            .compactMap { $0.trackStepID }
            .filter { stepID in
                trackSteps.contains { $0.id.uuidString == stepID }
            })
        
        let masteredCount = completedStepIDs.count
        let totalSteps = trackSteps.count
        let progressPercent = totalSteps > 0 ? Double(masteredCount) / Double(totalSteps) : 0.0
        let isComplete = masteredCount == totalSteps && totalSteps > 0
        
        // Find current/next step (first uncompleted step)
        let currentStep = trackSteps.first { step in
            !completedStepIDs.contains(step.id.uuidString)
        }
        
        let currentLesson = currentStep?.lessonTemplateID.flatMap { lessonID in
            allLessons.first { $0.id == lessonID }
        }
        
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
                                    width: max(0, min(geometry.size.width, geometry.size.width * progressPercent)),
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
                .fill(cardBackgroundColor)
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
    }
    
    // MARK: - Helper Functions
    private func trackColorForTitle(_ title: String) -> Color {
        // Generate a consistent color based on the track title
        let hash = title.hash
        let colors: [Color] = [
            .blue, .purple, .pink, .orange, .green, .mint, .teal, .cyan, .indigo
        ]
        let index = abs(hash) % colors.count
        return colors[index]
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
}
