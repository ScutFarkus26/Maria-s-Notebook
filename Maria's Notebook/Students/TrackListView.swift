// TrackListView.swift
// List view for managing tracks (now group-based)

import SwiftUI
import SwiftData

private struct GroupTrackRoute: Hashable {
    let subject: String
    let group: String
}

struct TrackListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var navigationPath = NavigationPath()
    
    // Query all lessons to count them per group
    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.group)]) 
    private var allLessons: [Lesson]
    
    // Get all group tracks
    private var groupTracks: [GroupTrack] {
        (try? GroupTrackService.getAllGroupTracks(modelContext: modelContext)) ?? []
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if groupTracks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tracks", systemImage: "list.bullet")
                    } description: {
                        Text("Mark groups as tracks in the Lessons view to see them here.")
                    }
                } else {
                    List {
                        ForEach(groupTracks, id: \.id) { groupTrack in
                            NavigationLink(value: GroupTrackRoute(subject: groupTrack.subject, group: groupTrack.group)) {
                                GroupTrackRow(groupTrack: groupTrack, allLessons: allLessons)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tracks")
        }
        .navigationDestination(for: GroupTrackRoute.self) { route in
            GroupTrackDetailView(subject: route.subject, group: route.group)
        }
    }
}

private struct GroupTrackRow: View {
    let groupTrack: GroupTrack
    let allLessons: [Lesson]
    
    private var lessons: [Lesson] {
        GroupTrackService.getLessonsForTrack(track: groupTrack, allLessons: allLessons)
    }
    
    var body: some View {
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
                    } else {
                        Label("Unordered", systemImage: "list.bullet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
