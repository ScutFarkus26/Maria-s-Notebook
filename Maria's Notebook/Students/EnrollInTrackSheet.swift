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
    @State private var availableTracks: [(subject: String, group: String, isSequential: Bool)] = []
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
                } else if availableTracks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tracks Available", systemImage: "list.bullet")
                    } description: {
                        Text("No tracks available. All groups are tracks by default unless explicitly disabled.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(availableTracks.enumerated()), id: \.offset) { index, track in
                            trackRow(track: track)
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
            // Get all available tracks (including groups without records - default behavior)
            availableTracks = try GroupTrackService.getAllAvailableTracks(
                from: allLessons,
                modelContext: modelContext
            )
        } catch {
            availableTracks = []
        }
        isLoading = false
    }
    
    // MARK: - Track Row
    @ViewBuilder
    private func trackRow(track: (subject: String, group: String, isSequential: Bool)) -> some View {
        // Get lessons for this track (filter and sort manually since we may not have a GroupTrack record)
        let lessons = allLessons
            .filter { lesson in
                lesson.subject.trimmed().caseInsensitiveCompare(track.subject.trimmed()) == .orderedSame &&
                lesson.group.trimmed().caseInsensitiveCompare(track.group.trimmed()) == .orderedSame
            }
            .sorted { lhs, rhs in
                if track.isSequential {
                    if lhs.orderInGroup != rhs.orderInGroup {
                        return lhs.orderInGroup < rhs.orderInGroup
                    }
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        
        let trackID = "\(track.subject)|\(track.group)"
        
        Button {
            enrollInTrack(subject: track.subject, group: track.group)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(track.subject) · \(track.group)")
                        .font(.headline)
                    
                    HStack(spacing: 8) {
                        Text("\(lessons.count) lesson\(lessons.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if track.isSequential {
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
    
    private func enrollInTrack(subject: String, group: String) {
        let studentIDStr = student.id.uuidString
        let trackID = "\(subject)|\(group)"
        
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
