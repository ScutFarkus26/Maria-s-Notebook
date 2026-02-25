// TrackListView.swift
// List view for managing tracks (now group-based)

import OSLog
import SwiftUI
import SwiftData

private struct GroupTrackRoute: Hashable {
    let subject: String
    let group: String
}

struct TrackListView: View {
    private static let logger = Logger.students

    @Environment(\.modelContext) private var modelContext
    @State private var navigationPath = NavigationPath()
    
    // Query all lessons to count them per group
    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.group)]) 
    private var allLessons: [Lesson]
    
    // Get all group tracks
    private var groupTracks: [GroupTrack] {
        do {
            return try GroupTrackService.getAllGroupTracks(modelContext: modelContext)
        } catch {
            Self.logger.warning("Failed to fetch group tracks: \(error)")
            return []
        }
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
                            .contextMenu {
                                Button {
                                    toggleSequential(groupTrack)
                                } label: {
                                    Label(
                                        groupTrack.isSequential ? "Mark as Unordered" : "Mark as Sequential",
                                        systemImage: groupTrack.isSequential ? "list.bullet" : "list.number"
                                    )
                                }

                                Divider()

                                Button(role: .destructive) {
                                    removeTrack(groupTrack)
                                } label: {
                                    Label("Remove Track", systemImage: "trash")
                                }
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

    private func toggleSequential(_ track: GroupTrack) {
        track.isSequential.toggle()
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save sequential toggle: \(error)")
        }
    }

    private func removeTrack(_ track: GroupTrack) {
        modelContext.delete(track)
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save track removal: \(error)")
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
                        .foregroundStyle(.secondary)
                    
                    if groupTrack.isSequential {
                        Label("Sequential", systemImage: "list.number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Unordered", systemImage: "list.bullet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
