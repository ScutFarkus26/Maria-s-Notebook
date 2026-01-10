// StudentProgressTab.swift
// Read-only progress tab showing student's track enrollments and progress (group-based tracks)

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct StudentProgressTab: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Inputs
    let student: Student
    var onLessonTapped: ((Lesson) -> Void)? = nil
    
    // MARK: - Queries
    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.group)])
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
    private var progressData: ProgressData {
        ProgressData(
            student: student,
            modelContext: modelContext,
            allLessons: allLessons
        )
    }
    
    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !progressData.activeEnrollments.isEmpty {
                    ForEach(progressData.activeEnrollments) { enrollment in
                        if let track = progressData.trackByID[enrollment.trackID] {
                            enrollmentCard(
                                enrollment: enrollment,
                                track: track,
                                progressData: progressData
                            )
                            .padding(.horizontal, 4)
                        }
                    }
                } else {
                    emptyStateView
                        .padding(.top, 60)
                }
            }
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Active Enrollments", systemImage: "chart.line.uptrend.xyaxis.circle")
                .foregroundStyle(.secondary)
        } description: {
            Text("Students are automatically enrolled in tracks when lessons are scheduled, presented, or marked as presented.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Enrollment Card
    @ViewBuilder
    private func enrollmentCard(
        enrollment: StudentTrackEnrollment,
        track: GroupTrack,
        progressData: ProgressData
    ) -> some View {
        let trackLessons = GroupTrackService.getLessonsForTrack(track: track, allLessons: allLessons)
        let totalLessons = trackLessons.count
        let masteredCount = GroupTrackProgressResolver.masteredCount(
            track: track,
            studentID: progressData.studentIDStr,
            lessons: allLessons,
            lessonPresentations: progressData.lpForStudent
        )
        let currentLesson = GroupTrackProgressResolver.currentLesson(
            track: track,
            studentID: progressData.studentIDStr,
            lessons: allLessons,
            lessonPresentations: progressData.lpForStudent
        )
        let lastObserved = progressData.lastObservedForTrack(trackID: enrollment.trackID, track: track)
        let progressPercent = totalLessons > 0 ? Double(masteredCount) / Double(totalLessons) : 0.0
        let isComplete = masteredCount == totalLessons && totalLessons > 0
        let subjectColor = AppColors.color(forSubject: track.subject)
        let cardKey = enrollment.trackID
        
        VStack(alignment: .leading, spacing: 16) {
            // Header with subject color accent
            HStack(spacing: 12) {
                // Subject icon/indicator
                ZStack {
                    Circle()
                        .fill(subjectColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: iconForSubject(track.subject))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(subjectColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.subject)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text(track.group)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Completion badge
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
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Progress visualization
            VStack(alignment: .leading, spacing: 12) {
                // Progress stats
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(masteredCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(subjectColor)
                    
                    Text("/ \(totalLessons)")
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
                                        : [subjectColor, subjectColor.opacity(0.7)],
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
                
                // Lesson dots visualization
                if totalLessons > 0 && totalLessons <= 30 {
                    HStack(spacing: 6) {
                        ForEach(0..<totalLessons, id: \.self) { index in
                            Circle()
                                .fill(index < masteredCount ? subjectColor : Color.secondary.opacity(0.2))
                                .frame(width: 8, height: 8)
                                .overlay {
                                    if index < masteredCount {
                                        Circle()
                                            .stroke(subjectColor.opacity(0.3), lineWidth: 2)
                                            .scaleEffect(1.3)
                                    }
                                }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            
            // Current lesson or completion status
            if track.isSequential {
                Divider()
                    .padding(.vertical, 4)
                
                if let currentLesson = currentLesson {
                    if let onLessonTapped = onLessonTapped {
                        Button {
                            onLessonTapped(currentLesson)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(subjectColor.opacity(0.7))
                                    .frame(width: 20)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Current Lesson")
                                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    
                                    Text(currentLesson.name.isEmpty ? "Untitled Lesson" : currentLesson.name)
                                        .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(subjectColor.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "book.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(subjectColor.opacity(0.7))
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current Lesson")
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
                                .fill(subjectColor.opacity(0.08))
                        )
                    }
                } else {
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
            }
            
            // Last observed date
            if let lastObserved = lastObserved {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    Text("Last observed \(lastObserved, style: .relative)")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
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
                            subjectColor.opacity(isComplete ? 0.3 : 0.15),
                            subjectColor.opacity(isComplete ? 0.15 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isComplete ? 2 : 1
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
    
    // MARK: - Helper: Icon for Subject
    private func iconForSubject(_ subject: String) -> String {
        let key = subject.normalizedForComparison()
        
        switch key {
        case "math", "mathematics": return "function"
        case "language", "language arts": return "text.book.closed.fill"
        case "science": return "flask.fill"
        case "practical life": return "hands.sparkles.fill"
        case "sensorial": return "eye.fill"
        case "geography": return "globe.americas.fill"
        case "history": return "book.closed.fill"
        case "art": return "paintpalette.fill"
        case "music": return "music.note"
        case "geometry": return "triangle.fill"
        case "botany": return "leaf.fill"
        case "zoology": return "pawprint.fill"
        case "reading": return "book.fill"
        case "writing": return "pencil"
        default: return "book.closed.circle.fill"
        }
    }
}

// MARK: - Progress Data Helper
private struct ProgressData {
    let studentIDStr: String
    let allEnrollments: [StudentTrackEnrollment]
    let activeEnrollments: [StudentTrackEnrollment]
    let trackByID: [String: GroupTrack]
    let lpForStudent: [LessonPresentation]
    let allLessons: [Lesson]
    
    init(student: Student, modelContext: ModelContext, allLessons: [Lesson]) {
        let studentIDStr = student.id.uuidString
        self.studentIDStr = studentIDStr
        self.allLessons = allLessons
        
        // Fetch all data with fetch-all + in-memory filtering
        let enrollments = (try? modelContext.fetch(FetchDescriptor<StudentTrackEnrollment>())) ?? []
        let groupTracks = (try? GroupTrackService.getAllGroupTracks(modelContext: modelContext)) ?? []
        let lps = (try? modelContext.fetch(FetchDescriptor<LessonPresentation>())) ?? []
        
        // Filter enrollments for this student
        let studentEnrollments = enrollments.filter { $0.studentID == studentIDStr }
        self.allEnrollments = studentEnrollments
        self.activeEnrollments = studentEnrollments.filter { $0.isActive }
        
        // Filter lesson presentations
        self.lpForStudent = lps.filter { $0.studentID == studentIDStr }
        
        // Create track dictionary by "subject|group" key
        var trackDict: [String: GroupTrack] = [:]
        for track in groupTracks {
            let key = "\(track.subject)|\(track.group)"
            trackDict[key] = track
        }
        self.trackByID = trackDict
    }
    
    func lastObservedForTrack(trackID: String, track: GroupTrack) -> Date? {
        // Find max lastObservedAt from lpForStudent where lessonID matches any lesson in the track
        let trackLessons = GroupTrackService.getLessonsForTrack(track: track, allLessons: allLessons)
        
        // Get lesson IDs from track
        let lessonIDs = Set(trackLessons.map { $0.id.uuidString })
        
        let relevantLPs = lpForStudent.filter { lp in
            // Primary: trackID matches (for legacy compatibility)
            if lp.trackID == trackID {
                return true
            }
            // Fallback: lessonID matches any lesson in the track
            if lessonIDs.contains(lp.lessonID) {
                return true
            }
            return false
        }
        
        return relevantLPs.compactMap { $0.lastObservedAt }.max()
    }
}
