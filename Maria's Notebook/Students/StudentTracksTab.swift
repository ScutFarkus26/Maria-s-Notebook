// StudentTracksTab.swift
// Track enrollments tab showing individual tracks with stats and activity

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct StudentTracksTab: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Inputs
    let student: Student
    
    // MARK: - State
    @State private var selectedEnrollment: StudentTrackEnrollment? = nil
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
    
    // MARK: - Queries
    @Query(sort: [SortDescriptor(\StudentTrackEnrollment.createdAt, order: .reverse)])
    private var allEnrollments: [StudentTrackEnrollment]
    
    @Query(sort: [SortDescriptor(\Track.title)])
    private var allTracks: [Track]
    
    @Query(sort: [SortDescriptor(\Presentation.presentedAt, order: .reverse)])
    private var allPresentations: [Presentation]
    
    @Query(sort: [SortDescriptor(\WorkContract.createdAt, order: .reverse)])
    private var allWorkContracts: [WorkContract]
    
    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var allNotes: [Note]
    
    @Query(sort: [SortDescriptor(\TrackStep.orderIndex)])
    private var allTrackSteps: [TrackStep]
    
    @Query(sort: [SortDescriptor(\Lesson.name)])
    private var allLessons: [Lesson]
    
    // MARK: - State
    @State private var animatedProgress: [String: Double] = [:]
    
    // MARK: - Computed Properties
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
    
    // MARK: - Computed Data
    private var enrollmentsForStudent: [StudentTrackEnrollment] {
        let studentIDString = student.id.uuidString
        return allEnrollments.filter { $0.studentID == studentIDString }
    }
    
    private var tracksByID: [String: Track] {
        Dictionary(uniqueKeysWithValues: allTracks.map { ($0.id.uuidString, $0) })
    }
    
    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if enrollmentsForStudent.isEmpty {
                    emptyStateView
                        .padding(.top, 60)
                } else {
                    ForEach(enrollmentsForStudent) { enrollment in
                        if let track = tracksByID[enrollment.trackID] {
                            enrollmentCard(
                                enrollment: enrollment,
                                track: track
                            )
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
        .sheet(item: $selectedEnrollment) { enrollment in
            if let track = tracksByID[enrollment.trackID] {
                StudentTrackDetailView(enrollment: enrollment, track: track)
                    .studentDetailSheetSizing()
            }
        }
        .sheet(item: $filterSheet) { sheet in
            switch sheet {
            case .presentations(let enrollment, let track):
                TrackFilteredListView(
                    enrollment: enrollment,
                    track: track,
                    filterType: .presentations,
                    allPresentations: allPresentations,
                    allWorkContracts: allWorkContracts,
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
                    allWorkContracts: allWorkContracts,
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
                    allWorkContracts: allWorkContracts,
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
            Label("No Track Enrollments", systemImage: "list.bullet.clipboard")
                .foregroundStyle(.secondary)
        } description: {
            Text("This student is not enrolled in any tracks yet.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
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
        let workContracts = allWorkContracts.filter {
            $0.trackID == trackIDString && $0.studentID == studentIDString
        }
        let notes = allNotes.filter {
            $0.studentTrackEnrollment?.id == enrollment.id
        }
        
        let presentationCount = presentations.count
        let workCount = workContracts.count
        let noteCount = notes.count
        let totalActivity = presentationCount + workCount + noteCount
        
        // Get last activity date
        let lastActivityDate: Date? = {
            var dates: [Date] = []
            dates.append(contentsOf: presentations.map { $0.presentedAt })
            dates.append(contentsOf: workContracts.compactMap { $0.completedAt ?? $0.createdAt })
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
                // Verify this step belongs to this track
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
        
        let cardKey = enrollment.trackID
        
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
                
                // Completion badge (from progress tab) or Active/Inactive status badge
                if isComplete && totalSteps > 0 {
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
                } else if enrollment.isActive {
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
            
            // Progress visualization (from progress tab)
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
                                    width: geometry.size.width * (animatedProgress[cardKey] ?? 0.0),
                                    height: 12
                                )
                                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: animatedProgress[cardKey])
                            
                            // Glow effect for completed tracks
                            if isComplete && (animatedProgress[cardKey] ?? 0) >= 1.0 {
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
            
            // Current/Next lesson (from progress tab)
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
                                icon: "presentation",
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
        .onAppear {
            // Animate progress on appear
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.1)) {
                animatedProgress[cardKey] = progressPercent
            }
        }
        .onChange(of: progressPercent) { oldValue, newValue in
            // Animate when progress changes
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                animatedProgress[cardKey] = newValue
            }
        }
    }
    
    // MARK: - Stat Badge
    private func statBadge(count: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .foregroundStyle(color)
            
            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Track Color Helper
    private func trackColorForTitle(_ title: String) -> Color {
        // Generate a consistent color based on the track title
        // This provides visual variety while being deterministic
        let hash = title.hash
        let colors: [Color] = [
            .blue, .purple, .pink, .orange, .green, .mint, .teal, .cyan, .indigo
        ]
        let index = abs(hash) % colors.count
        return colors[index]
    }
}

// MARK: - Track Filtered List View
struct TrackFilteredListView: View {
    let enrollment: StudentTrackEnrollment
    let track: Track
    let filterType: FilterType
    
    let allPresentations: [Presentation]
    let allWorkContracts: [WorkContract]
    let allNotes: [Note]
    let allLessons: [Lesson]
    let onDismiss: (() -> Void)?
    
    enum FilterType {
        case presentations
        case work
        case notes
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    init(
        enrollment: StudentTrackEnrollment,
        track: Track,
        filterType: FilterType,
        allPresentations: [Presentation],
        allWorkContracts: [WorkContract],
        allNotes: [Note],
        allLessons: [Lesson],
        onDismiss: (() -> Void)? = nil
    ) {
        self.enrollment = enrollment
        self.track = track
        self.filterType = filterType
        self.allPresentations = allPresentations
        self.allWorkContracts = allWorkContracts
        self.allNotes = allNotes
        self.allLessons = allLessons
        self.onDismiss = onDismiss
    }
    
    @State private var selectedPresentation: Presentation? = nil
    @State private var selectedContract: WorkContract? = nil
    @State private var selectedNote: Note? = nil
    
    private var trackIDString: String { track.id.uuidString }
    private var studentIDString: String { enrollment.studentID }
    
    private var filteredPresentations: [Presentation] {
        allPresentations.filter {
            $0.trackID == trackIDString && $0.studentIDs.contains(studentIDString)
        }
    }
    
    private var filteredWorkContracts: [WorkContract] {
        allWorkContracts.filter {
            $0.trackID == trackIDString && $0.studentID == studentIDString
        }
    }
    
    private var filteredNotes: [Note] {
        allNotes.filter {
            $0.studentTrackEnrollment?.id == enrollment.id
        }
    }
    
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: allLessons.map { ($0.id, $0) })
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if filterType == .presentations {
                        ForEach(filteredPresentations) { presentation in
                            presentationRow(presentation)
                                .onTapGesture {
                                    selectedPresentation = presentation
                                }
                        }
                    } else if filterType == .work {
                        ForEach(filteredWorkContracts) { contract in
                            workRow(contract)
                                .onTapGesture {
                                    selectedContract = contract
                                }
                        }
                    } else if filterType == .notes {
                        ForEach(filteredNotes) { note in
                            noteRow(note)
                                .onTapGesture {
                                    selectedNote = note
                                }
                        }
                    }
                    
                    if isEmpty {
                        emptyStateView
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss?()
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $selectedPresentation) { presentation in
            PresentationDetailSheet(presentationID: presentation.id) {
                selectedPresentation = nil
            }
            .studentDetailSheetSizing()
        }
        .sheet(item: $selectedContract) { contract in
            WorkContractDetailSheet(contract: contract) {
                selectedContract = nil
            }
            .studentDetailSheetSizing()
        }
        .sheet(item: $selectedNote) { note in
            NoteDetailView(note: note) {
                selectedNote = nil
            }
            .studentDetailSheetSizing()
        }
    }
    
    private var title: String {
        switch filterType {
        case .presentations:
            return "Presentations - \(track.title)"
        case .work:
            return "Work - \(track.title)"
        case .notes:
            return "Notes - \(track.title)"
        }
    }
    
    private var isEmpty: Bool {
        switch filterType {
        case .presentations:
            return filteredPresentations.isEmpty
        case .work:
            return filteredWorkContracts.isEmpty
        case .notes:
            return filteredNotes.isEmpty
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No \(filterTypeName)", systemImage: iconName)
                .foregroundStyle(.secondary)
        } description: {
            Text("No \(filterTypeName.lowercased()) recorded for this track yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var filterTypeName: String {
        switch filterType {
        case .presentations: return "Presentations"
        case .work: return "Work"
        case .notes: return "Notes"
        }
    }
    
    private var iconName: String {
        switch filterType {
        case .presentations: return "person.3.fill"
        case .work: return "briefcase.fill"
        case .notes: return "note.text"
        }
    }
    
    private func presentationRow(_ presentation: Presentation) -> some View {
        let lesson = UUID(uuidString: presentation.lessonID).flatMap { lessonsByID[$0] }
        let title = presentation.lessonTitleSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? lesson?.name ?? "Lesson"
        
        return HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(Self.dateFormatter.string(from: presentation.presentedAt))
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func workRow(_ contract: WorkContract) -> some View {
        return HStack(spacing: 12) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(contract.title ?? "Work Contract")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    Text(contract.status.rawValue.capitalized)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    if let completedAt = contract.completedAt {
                        Text("• \(Self.dateFormatter.string(from: completedAt))")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func noteRow(_ note: Note) -> some View {
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 16))
                .foregroundStyle(.yellow)
                .frame(width: 24)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(note.body)
                    .font(.system(size: AppTheme.FontSize.callout, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                
                Text(Self.dateFormatter.string(from: note.updatedAt))
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.yellow.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
        )
    }
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}

// MARK: - Note Detail View (simple wrapper if needed)
private struct NoteDetailView: View, Identifiable {
    let note: Note
    var onDone: (() -> Void)? = nil
    
    var id: UUID { note.id }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(note.body)
                        .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding()
                }
            }
            .navigationTitle("Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDone?()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    context.insert(student)
    return StudentTracksTab(student: student)
        .previewEnvironment(using: container)
        .padding()
}
