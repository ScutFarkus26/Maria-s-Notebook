// GroupTrackSettingsSheet.swift
// Sheet for configuring whether a group is a track and if it's sequential

import SwiftUI
import CoreData
import OSLog

struct GroupTrackSettingsSheet: View {
    private static let logger = Logger.lessons

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let subject: String
    let group: String
    
    @State private var isTrack: Bool = false
    @State private var isSequential: Bool = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use as CDTrackEntity", isOn: $isTrack)
                    
                    if isTrack {
                        Picker("CDTrackEntity Type", selection: $isSequential) {
                            Text("Sequential (order matters)").tag(true)
                            Text("Group (no order)").tag(false)
                        }
                        .pickerStyle(.segmented)
                        
                        Text(isSequential 
                            ? "Lessons must be completed in order. Students progress through lessons sequentially."
                            : "Lessons can be completed in any order. This is just a collection of related lessons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("This group will not be available as a track for student enrollment.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Group: \(group)")
                } footer: {
                    if isTrack {
                        Text("Students can be enrolled in this track to track their progress through these lessons.")
                    }
                }
            }
            .navigationTitle("CDTrackEntity Settings")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                    }
                }
            }
            .task {
                loadSettings()
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }
    
    private func loadSettings() {
        do {
            // Default behavior: all groups are tracks (sequential) unless explicitly disabled
            if let track = try GroupTrackService.cdGetGroupTrack(
                subject: subject,
                group: group,
                context: viewContext
            ) {
                // If a record exists, check if it's explicitly disabled
                isTrack = !track.isExplicitlyDisabled
                isSequential = track.isSequential
            } else {
                // No record exists = default behavior = is a track (sequential)
                isTrack = true
                isSequential = true
            }
        } catch {
            Self.logger.error("Failed to load track settings: \(error)")
            // On error, default to true (is a track, sequential)
            isTrack = true
            isSequential = true
        }
    }
    
    private func saveSettings() {
        do {
            if isTrack {
                // User wants this to be a track - create or update record
                let track = try GroupTrackService.cdGetOrCreateGroupTrack(
                    subject: subject,
                    group: group,
                    context: viewContext
                )
                track.isSequential = isSequential
                track.isExplicitlyDisabled = false // Explicitly enabled
            } else {
                // User unchecked "Use as CDTrackEntity" - explicitly disable
                let track = try GroupTrackService.cdGetOrCreateGroupTrack(
                    subject: subject,
                    group: group,
                    context: viewContext
                )
                track.isExplicitlyDisabled = true
            }
            
            try viewContext.save()
            dismiss()
        } catch {
            Self.logger.error("Failed to save track settings: \(error)")
        }
    }
}
