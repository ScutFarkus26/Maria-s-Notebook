// EnrollInTrackSheet.swift
// Sheet for enrolling a student in a group-based track

import SwiftUI
import SwiftData

struct EnrollInTrackSheet: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Inputs
    let student: Student
    let existingEnrollments: [StudentTrackEnrollment]
    
    // MARK: - State
    @State private var groupTracks: [GroupTrack] = []
    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.group)])
    private var allLessons: [Lesson]
    @State private var isLoading = true
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if groupTracks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tracks Available", systemImage: "list.bullet")
                    } description: {
                        Text("No tracks found. Mark groups as tracks in the Lessons view first.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupTracks, id: \.id) { groupTrack in
                            trackRow(groupTrack: groupTrack)
                        }
                    }
                }
            }
            .navigationTitle("Enroll in Track")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                loadTracks()
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 420)
            #endif
        }
    }
    
    // MARK: - Data Loading
    private func loadTracks() {
        do {
            groupTracks = try GroupTrackService.getAllGroupTracks(modelContext: modelContext)
        } catch {
            groupTracks = []
        }
        isLoading = false
    }
    
    // MARK: - Track Row
    @ViewBuilder
    private func trackRow(groupTrack: GroupTrack) -> some View {
        let lessons = GroupTrackService.getLessonsForTrack(track: groupTrack, allLessons: allLessons)
        let trackID = "\(groupTrack.subject)|\(groupTrack.group)"
        
        Button {
            enrollInTrack(groupTrack: groupTrack)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(groupTrack.subject) · \(groupTrack.group)")
                        .font(.headline)
                    
                    HStack(spacing: 8) {
                        Text("\(lessons.count) lesson\(lessons.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if groupTrack.isSequential {
                            Label("Sequential", systemImage: "list.number")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Show enrollment status
                if let enrollment = existingEnrollmentFor(trackID: trackID) {
                    if enrollment.isActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Inactive", systemImage: "circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Methods
    private func existingEnrollmentFor(trackID: String) -> StudentTrackEnrollment? {
        existingEnrollments.first { $0.trackID == trackID }
    }
    
    private func enrollInTrack(groupTrack: GroupTrack) {
        let studentIDStr = student.id.uuidString
        let trackID = "\(groupTrack.subject)|\(groupTrack.group)"
        
        // Check if enrollment already exists
        if let existingEnrollment = existingEnrollmentFor(trackID: trackID) {
            // Reactivate existing enrollment
            existingEnrollment.isActive = true
            if existingEnrollment.startedAt == nil {
                existingEnrollment.startedAt = Date()
            }
        } else {
            // Create new enrollment
            let newEnrollment = StudentTrackEnrollment(
                studentID: studentIDStr,
                trackID: trackID,
                startedAt: Date(),
                isActive: true
            )
            modelContext.insert(newEnrollment)
        }
        
        // Save and dismiss
        try? modelContext.save()
        dismiss()
    }
}
