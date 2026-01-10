// StudentHistoryTab.swift
// History tab showing student's finished track enrollments

import SwiftUI
import SwiftData

struct StudentHistoryTab: View {
    let student: Student
    
    @Query(sort: [SortDescriptor(\StudentTrackEnrollment.createdAt, order: .reverse)])
    private var allEnrollments: [StudentTrackEnrollment]
    
    @Query(sort: [SortDescriptor(\Track.title)])
    private var allTracks: [Track]
    
    @State private var selectedEnrollment: StudentTrackEnrollment?
    
    private var finishedEnrollments: [StudentTrackEnrollment] {
        let sid = student.id.uuidString
        return allEnrollments.filter { $0.studentID == sid && !$0.isActive }
    }
    
    private var tracksByID: [String: Track] {
        Dictionary(uniqueKeysWithValues: allTracks.map { ($0.id.uuidString, $0) })
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if finishedEnrollments.isEmpty {
                    ContentUnavailableView {
                        Label("No History", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    } description: {
                        Text("No finished tracks found.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Finished Tracks", systemImage: "flag.checkered")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        
                        ForEach(finishedEnrollments) { enrollment in
                            if let track = tracksByID[enrollment.trackID] {
                                finishedRow(enrollment: enrollment, track: track)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedEnrollment = enrollment
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $selectedEnrollment) { enrollment in
            if let track = tracksByID[enrollment.trackID] {
                StudentTrackDetailView(enrollment: enrollment, track: track)
                    .studentDetailSheetSizing()
            }
        }
    }
    
    private func finishedRow(enrollment: StudentTrackEnrollment, track: Track) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.secondary.opacity(0.5))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(.primary.opacity(0.8))
                
                if let notes = enrollment.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.05))
        )
    }
}
