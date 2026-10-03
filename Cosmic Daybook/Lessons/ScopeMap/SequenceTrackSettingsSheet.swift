// SequenceTrackSettingsSheet.swift
// Sheet for configuring whether a sequence is a track and if it's sequential

import SwiftUI
import CoreData
import OSLog

struct SequenceTrackSettingsSheet: View {
    private static let logger = Logger.lessons

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let area: String
    let sequence: String
    
    @State private var isTrack: Bool = false
    @State private var isSequential: Bool = true
    @State private var requiresPractice: Bool = true
    @State private var requiresConfirmation: Bool = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use as Track", isOn: $isTrack)
                    
                    if isTrack {
                        Picker("Track Type", selection: $isSequential) {
                            Text("Sequential (order matters)").tag(true)
                            Text("Sequence (no order)").tag(false)
                        }
                        .pickerStyle(.segmented)
                        
                        Text(isSequential 
                            ? "Lessons must be completed in order. Students progress through lessons sequentially."
                            : "Lessons can be completed in any order. This is just a collection of related lessons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("This sequence will not be available as a track for student enrollment.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Sequence: \(sequence)")
                } footer: {
                    if isTrack {
                        Text("Students can be enrolled in this track to track their progress through these lessons.")
                    }
                }

                Section {
                    Toggle("Requires Follow-Up Practice", isOn: $requiresPractice)
                    Toggle("Requires Teacher Confirmation", isOn: $requiresConfirmation)

                    if !requiresPractice && !requiresConfirmation {
                        Text("The next lesson in this sequence will unlock immediately after presentation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Individual lessons can override these settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Progression Rules")
                } footer: {
                    Text("Controls what students must complete before advancing to the next lesson in this sequence.")
                }
            }
            .navigationTitle("Track Settings")
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
            if let track = try SequenceTrackService.cdGetSequenceTrack(
                area: area,
                sequence: sequence,
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

        // Load progression rules
        if let gs = CDLessonSequenceSettings.find(
            area: area,
            sequence: sequence,
            context: viewContext
        ) {
            requiresPractice = gs.requiresPractice
            requiresConfirmation = gs.requiresTeacherConfirmation
        }
    }
    
    private func saveSettings() {
        do {
            if isTrack {
                // User wants this to be a track - create or update record
                let track = try SequenceTrackService.cdGetOrCreateSequenceTrack(
                    area: area,
                    sequence: sequence,
                    context: viewContext
                )
                track.isSequential = isSequential
                track.isExplicitlyDisabled = false // Explicitly enabled
            } else {
                // User unchecked "Use as Track" - explicitly disable
                let track = try SequenceTrackService.cdGetOrCreateSequenceTrack(
                    area: area,
                    sequence: sequence,
                    context: viewContext
                )
                track.isExplicitlyDisabled = true
            }

            // Save progression rules
            let gs = CDLessonSequenceSettings.find(
                area: area,
                sequence: sequence,
                context: viewContext
            ) ?? CDLessonSequenceSettings(context: viewContext)
            gs.area = area
            gs.sequence = sequence
            gs.requiresPractice = requiresPractice
            gs.requiresTeacherConfirmation = requiresConfirmation
            gs.modifiedAt = Date()

            if viewContext.safeSave() {
                dismiss()
            }
        } catch {
            Self.logger.error("Failed to save track settings: \(error)")
        }
    }
}
