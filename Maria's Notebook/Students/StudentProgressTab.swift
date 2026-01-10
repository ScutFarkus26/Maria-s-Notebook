// StudentProgressTab.swift
// Read-only progress tab showing student's track enrollments and progress (group-based tracks)

import SwiftUI
import SwiftData

struct StudentProgressTab: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Inputs
    let student: Student
    
    // MARK: - State
    @State private var showingEnrollSheet = false
    
    // MARK: - Queries
    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.group)])
    private var allLessons: [Lesson]
    
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
        List {
            // Enrollments Management Section
            enrollmentsSection()
            
            // Progress Sections
            if !progressData.activeEnrollments.isEmpty {
                ForEach(progressData.activeEnrollments) { enrollment in
                    if let track = progressData.trackByID[enrollment.trackID] {
                        enrollmentSection(
                            enrollment: enrollment,
                            track: track,
                            progressData: progressData
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .sheet(isPresented: $showingEnrollSheet) {
            EnrollInTrackSheet(
                student: student,
                existingEnrollments: progressData.allEnrollments
            )
        }
    }
    
    // MARK: - Enrollments Section
    @ViewBuilder
    private func enrollmentsSection() -> some View {
        Section("Enrollments") {
            if progressData.activeEnrollments.isEmpty {
                Text("No active enrollments")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Show all enrollments (active and inactive)
            if !progressData.allEnrollments.isEmpty {
                ForEach(progressData.allEnrollments) { enrollment in
                    if let track = progressData.trackByID[enrollment.trackID] {
                        enrollmentRow(enrollment: enrollment, track: track)
                    }
                }
            }
            
            // Always show Add Enrollment button
            Button {
                showingEnrollSheet = true
            } label: {
                Label("Add Enrollment", systemImage: "plus.circle.fill")
            }
        }
    }
    
    // MARK: - Enrollment Row
    @ViewBuilder
    private func enrollmentRow(enrollment: StudentTrackEnrollment, track: GroupTrack) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(track.subject) · \(track.group)")
                    .font(.headline)
                
                HStack(spacing: 8) {
                    // Status badge
                    if enrollment.isActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Inactive", systemImage: "circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Started date
                    if let startDate = enrollment.startedAt ?? enrollment.createdAt as Date? {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Started \(startDate, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Deactivate button (only for active enrollments)
            if enrollment.isActive {
                Button {
                    deactivateEnrollment(enrollment)
                } label: {
                    Text("Deactivate")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // MARK: - Actions
    private func deactivateEnrollment(_ enrollment: StudentTrackEnrollment) {
        enrollment.isActive = false
        try? modelContext.save()
    }
    
    // MARK: - Section Builder
    @ViewBuilder
    private func enrollmentSection(
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
        
        Section {
            // Track Title
            Text("\(track.subject) · \(track.group)")
                .font(.headline)
            
            // Progress: masteredCount/totalLessons
            HStack {
                Text("Progress:")
                Spacer()
                Text("\(masteredCount)/\(totalLessons)")
                    .fontWeight(.medium)
            }
            
            // Current Lesson (only for sequential tracks)
            if track.isSequential {
                if let currentLesson = currentLesson {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Lesson:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(currentLesson.name.isEmpty ? "Untitled Lesson" : currentLesson.name)
                            .fontWeight(.medium)
                    }
                } else {
                    HStack {
                        Text("Current Lesson:")
                        Spacer()
                        Text("All lessons mastered")
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                }
            }
            
            // Last Observed
            if let lastObserved = lastObserved {
                HStack {
                    Text("Last Observed:")
                    Spacer()
                    Text(lastObserved, style: .date)
                        .foregroundColor(.secondary)
                }
            }
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
