// EnrollInTrackSheet.swift
// Sheet for enrolling a student in a track

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
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tracks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tracks Available", systemImage: "list.bullet")
                    } description: {
                        Text("No tracks found. Create tracks first.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(tracks) { track in
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
        // Fetch all tracks using fetch-all approach (no predicates with UUID->String conversions)
        do {
            let descriptor = FetchDescriptor<Track>(
                sortBy: [SortDescriptor(\.title, order: .forward)]
            )
            tracks = try modelContext.fetch(descriptor)
        } catch {
            tracks = []
        }
        isLoading = false
    }
    
    // MARK: - Track Row
    @ViewBuilder
    private func trackRow(track: Track) -> some View {
        Button {
            enrollInTrack(track)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.headline)
                    
                    let stepCount = track.steps?.count ?? 0
                    Text("\(stepCount) step\(stepCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Show enrollment status
                if let enrollment = existingEnrollmentFor(trackID: track.id.uuidString) {
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
    
    private func enrollInTrack(_ track: Track) {
        let studentIDStr = student.id.uuidString
        let trackIDStr = track.id.uuidString
        
        // Check if enrollment already exists
        if let existingEnrollment = existingEnrollmentFor(trackID: trackIDStr) {
            // Reactivate existing enrollment
            existingEnrollment.isActive = true
            if existingEnrollment.startedAt == nil {
                existingEnrollment.startedAt = Date()
            }
        } else {
            // Create new enrollment
            let newEnrollment = StudentTrackEnrollment(
                studentID: studentIDStr,
                trackID: trackIDStr,
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
