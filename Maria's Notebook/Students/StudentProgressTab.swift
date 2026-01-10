// StudentProgressTab.swift
// Read-only progress tab showing student's track enrollments and progress (group-based tracks)

import SwiftUI
import SwiftData

struct StudentProgressTab: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Inputs
    let student: Student
    
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
            // Progress Sections (read-only)
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
            } else {
                ContentUnavailableView {
                    Label("No Active Enrollments", systemImage: "list.bullet")
                } description: {
                    Text("Students are automatically enrolled in tracks when lessons are scheduled, presented, or marked as presented.")
                }
            }
        }
        .listStyle(.plain)
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
