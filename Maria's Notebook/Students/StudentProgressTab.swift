// StudentProgressTab.swift
// Read-only progress tab showing student's track enrollments and progress

import SwiftUI
import SwiftData

struct StudentProgressTab: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Inputs
    let student: Student
    
    // MARK: - State
    @State private var showingEnrollSheet = false
    
    // MARK: - Computed Data
    private var progressData: ProgressData {
        ProgressData(
            student: student,
            modelContext: modelContext
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
    private func enrollmentRow(enrollment: StudentTrackEnrollment, track: Track) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
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
        track: Track,
        progressData: ProgressData
    ) -> some View {
        let totalSteps = TrackProgressResolver.totalSteps(track: track)
        let masteredCount = TrackProgressResolver.masteredCount(
            track: track,
            studentID: progressData.studentIDStr,
            lessonPresentations: progressData.lpForStudent
        )
        let currentStep = TrackProgressResolver.currentStep(
            track: track,
            studentID: progressData.studentIDStr,
            lessonPresentations: progressData.lpForStudent
        )
        let lastObserved = progressData.lastObservedForTrack(trackID: track.id.uuidString)
        
        Section {
            // Track Title
            Text(track.title)
                .font(.headline)
            
            // Progress: masteredCount/totalSteps
            HStack {
                Text("Progress:")
                Spacer()
                Text("\(masteredCount)/\(totalSteps)")
                    .fontWeight(.medium)
            }
            
            // Current Step
            if let currentStep = currentStep {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Step:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack {
                        Text("Step \(currentStep.orderIndex + 1)")
                            .fontWeight(.medium)
                        if let lessonTemplateID = currentStep.lessonTemplateID,
                           let lesson = progressData.lessonsByID[lessonTemplateID] {
                            Text("• \(lesson.name)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                HStack {
                    Text("Current Step:")
                    Spacer()
                    Text("All steps mastered")
                        .foregroundColor(.green)
                        .fontWeight(.medium)
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
    let trackByID: [String: Track]
    let lpForStudent: [LessonPresentation]
    let lessonsByID: [UUID: Lesson]
    
    init(student: Student, modelContext: ModelContext) {
        let studentIDStr = student.id.uuidString
        self.studentIDStr = studentIDStr
        
        // Fetch all data with fetch-all + in-memory filtering
        let enrollments = (try? modelContext.fetch(FetchDescriptor<StudentTrackEnrollment>())) ?? []
        let tracks = (try? modelContext.fetch(FetchDescriptor<Track>())) ?? []
        let lps = (try? modelContext.fetch(FetchDescriptor<LessonPresentation>())) ?? []
        let lessons = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
        
        // Filter enrollments for this student
        let studentEnrollments = enrollments.filter { $0.studentID == studentIDStr }
        self.allEnrollments = studentEnrollments
        self.activeEnrollments = studentEnrollments.filter { $0.isActive }
        
        // Filter lesson presentations
        self.lpForStudent = lps.filter { $0.studentID == studentIDStr }
        
        // Create track dictionary
        self.trackByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id.uuidString, $0) })
        
        // Create lessons dictionary
        self.lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }
    
    func lastObservedForTrack(trackID: String) -> Date? {
        // Find max lastObservedAt from lpForStudent where:
        // 1. lp.trackID == trackID (primary)
        // OR
        // 2. lp.lessonID matches any step.lessonTemplateID in the track (fallback)
        guard let track = trackByID[trackID] else { return nil }
        
        let steps = (track.steps ?? []).sorted { $0.orderIndex < $1.orderIndex }
        let stepLessonIDs = Set(steps.compactMap { $0.lessonTemplateID?.uuidString })
        
        let relevantLPs = lpForStudent.filter { lp in
            // Primary: trackID matches
            if lp.trackID == trackID {
                return true
            }
            // Fallback: lessonID matches any step's lessonTemplateID
            if stepLessonIDs.contains(lp.lessonID) {
                return true
            }
            return false
        }
        
        return relevantLPs.compactMap { $0.lastObservedAt }.max()
    }
}

