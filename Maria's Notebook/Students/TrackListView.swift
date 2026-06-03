// TrackListView.swift
// List view for managing tracks (now sequence-based)

import OSLog
import SwiftUI
import CoreData

private struct SequenceTrackRoute: Hashable {
    let area: String
    let sequence: String
}

struct TrackListView: View {
    private static let logger = Logger.students

    @Environment(\.managedObjectContext) private var viewContext
    @State private var navigationPath = NavigationPath()
    
    // Query all lessons to count them per sequence
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
        NSSortDescriptor(keyPath: \CDLesson.sequence, ascending: true)
    ])
    private var allLessons: FetchedResults<CDLesson>
    
    // Get all sequence tracks
    private var sequenceTracks: [CDSequenceTrack] {
        viewContext.safeFetch(CDFetchRequest(CDSequenceTrackEntity.self))
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if sequenceTracks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tracks", systemImage: "list.bullet")
                    } description: {
                        Text("Mark groups as tracks in the Lessons view to see them here.")
                    }
                } else {
                    List {
                        ForEach(sequenceTracks, id: \.id) { sequenceTrack in
                            NavigationLink(
                                value: SequenceTrackRoute(area: sequenceTrack.area, sequence: sequenceTrack.sequence)
                            ) {
                                SequenceTrackRow(sequenceTrack: sequenceTrack, allLessons: Array(allLessons))
                            }
                            .contextMenu {
                                Button {
                                    toggleSequential(sequenceTrack)
                                } label: {
                                    Label(
                                        sequenceTrack.isSequential ? "Mark as Unordered" : "Mark as Sequential",
                                        systemImage: sequenceTrack.isSequential ? "list.bullet" : "list.number"
                                    )
                                }

                                Divider()

                                Button(role: .destructive) {
                                    removeTrack(sequenceTrack)
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
        .navigationDestination(for: SequenceTrackRoute.self) { route in
            SequenceTrackDetailView(area: route.area, sequence: route.sequence)
        }
    }

    private func toggleSequential(_ track: CDSequenceTrack) {
        track.isSequential.toggle()
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save sequential toggle: \(error)")
        }
    }

    private func removeTrack(_ track: CDSequenceTrack) {
        viewContext.delete(track)
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save track removal: \(error)")
        }
    }
}

private struct SequenceTrackRow: View {
    let sequenceTrack: CDSequenceTrack
    let allLessons: [CDLesson]
    
    private var lessons: [CDLesson] {
        SequenceTrackService.getLessonsForTrack(track: sequenceTrack, allLessons: allLessons)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(sequenceTrack.area) · \(sequenceTrack.sequence)")
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text("\(lessons.count) lesson\(lessons.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if sequenceTrack.isSequential {
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
