// TrackListView.swift
// List view for managing tracks

import SwiftUI
import SwiftData

private struct TrackRoute: Hashable {
    let id: UUID
}

struct TrackListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTrackID: UUID?
    @State private var showingCreateSheet = false
    @State private var showingImportSheet = false
    @State private var navigationPath = NavigationPath()
    @Query(sort: [SortDescriptor(\Track.title, order: .forward)]) private var tracks: [Track]
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if tracks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tracks", systemImage: "list.bullet")
                    } description: {
                        Text("Create a track to get started.")
                    }
                } else {
                    List {
                        ForEach(tracks) { track in
                            NavigationLink(value: TrackRoute(id: track.id)) {
                                TrackRow(track: track)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tracks")
            .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Label("Add Track", systemImage: "plus")
                    }
                    
                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Import Track…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Add Track", systemImage: "plus")
                }
            }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateTrackSheet()
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportTrackFromLessonsSheet { trackID in
                // Navigate to the newly created track
                navigationPath.append(TrackRoute(id: trackID))
            }
        }
        .navigationDestination(for: TrackRoute.self) { route in
            // Try to find track in query first, fallback to direct fetch if needed
            if let track = tracks.first(where: { $0.id == route.id }) {
                TrackDetailView(track: track)
            } else {
                // Fallback: fetch directly from modelContext (handles case where query hasn't updated yet)
                let targetID = route.id
                let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.id == targetID })
                if let track = try? modelContext.fetch(descriptor).first {
                    TrackDetailView(track: track)
                } else {
                    ContentUnavailableView("Track Not Found", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }
}

private struct TrackRow: View {
    let track: Track
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title.isEmpty ? "Untitled Track" : track.title)
                    .font(.headline)
                
                let stepCount = track.steps?.count ?? 0
                Text("\(stepCount) step\(stepCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct CreateTrackSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Track") {
                    TextField("Title", text: $title)
                }
            }
            .navigationTitle("New Track")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTrack()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func createTrack() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        let newTrack = Track(title: trimmedTitle)
        modelContext.insert(newTrack)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to create track: \(error)")
        }
    }
}

