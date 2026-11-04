// SequenceRulesSheet.swift
// The progression rules of one sequence: what a child must do after a lesson
// before the next one in the sequence unlocks. Until 2026-11-03 this sheet
// also made the sequence a "track" (the retired track entities); the rules
// live on `CDLessonSequenceSettings`, one row per area and sequence.

import SwiftUI
import CoreData

struct SequenceRulesSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let area: String
    let sequence: String

    @State private var requiresPractice: Bool = true
    @State private var requiresConfirmation: Bool = true

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("Sequence: \(sequence)")
                } footer: {
                    Text("Controls what students must complete before advancing to the next lesson in this sequence.")
                }
            }
            .navigationTitle("Progression Rules")
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
        .frame(minWidth: 400, minHeight: 240)
        #endif
    }

    private func loadSettings() {
        if let settings = CDLessonSequenceSettings.find(
            area: area,
            sequence: sequence,
            context: viewContext
        ) {
            requiresPractice = settings.requiresPractice
            requiresConfirmation = settings.requiresTeacherConfirmation
        }
    }

    private func saveSettings() {
        let settings = CDLessonSequenceSettings.find(
            area: area,
            sequence: sequence,
            context: viewContext
        ) ?? CDLessonSequenceSettings(context: viewContext)
        settings.area = area
        settings.sequence = sequence
        settings.requiresPractice = requiresPractice
        settings.requiresTeacherConfirmation = requiresConfirmation
        settings.modifiedAt = Date()

        if viewContext.safeSave() {
            dismiss()
        }
    }
}
