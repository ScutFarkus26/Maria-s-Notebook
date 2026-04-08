// WorkCycleEntrySheet.swift
// Sheet for logging a student's activity during a work cycle.

import SwiftUI

struct WorkCycleEntrySheet: View {
    let studentID: UUID
    let studentName: String
    let onSave: (String, SocialMode, ConcentrationLevel, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var activity: String = ""
    @State private var socialMode: SocialMode = .independent
    @State private var concentration: ConcentrationLevel = .focused
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)
                        Text(studentName)
                            .font(.headline)
                    }
                }

                Section("Activity") {
                    TextField("What are they working on?", text: $activity)
                        .textFieldStyle(.plain)
                }

                Section("Social Mode") {
                    Picker("Social Mode", selection: $socialMode) {
                        ForEach(SocialMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Concentration") {
                    Picker("Concentration Level", selection: $concentration) {
                        ForEach(ConcentrationLevel.allCases) { level in
                            HStack(spacing: 6) {
                                Image(systemName: level.icon)
                                    .foregroundStyle(level.color)
                                Text(level.displayName)
                            }
                            .tag(level)
                        }
                    }
                    .pickerStyle(.menu)

                    // Visual indicator
                    HStack(spacing: 4) {
                        ForEach(ConcentrationLevel.allCases) { level in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(level == concentration ? level.color : level.color.opacity(0.2))
                                .frame(height: 6)
                        }
                    }
                }

                Section("Notes (Optional)") {
                    TextField("Additional observations", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Activity")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(activity, socialMode, concentration, nil)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
