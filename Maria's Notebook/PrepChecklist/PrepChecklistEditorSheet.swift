// PrepChecklistEditorSheet.swift
// Sheet to create or edit a prep checklist's metadata (name, icon, schedule type).

import SwiftUI
import CoreData

struct PrepChecklistEditorSheet: View {
    @Bindable var viewModel: PrepChecklistViewModel
    let checklist: CDPrepChecklist?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var icon: String = "checklist.checked"
    @State private var colorHex: String = "#007AFF"
    @State private var scheduleType: PrepScheduleType = .daily
    @State private var notes: String = ""

    private var isEditing: Bool { checklist != nil }

    private let iconOptions = [
        "checklist.checked", "sun.max", "moon.stars", "leaf",
        "tray.full", "books.vertical", "paintbrush", "scissors",
        "globe.americas", "figure.walk", "music.note", "star"
    ]

    private let colorOptions: [(name: String, hex: String)] = [
        ("Blue", "#007AFF"),
        ("Green", "#34C759"),
        ("Orange", "#FF9500"),
        ("Purple", "#AF52DE"),
        ("Red", "#FF3B30"),
        ("Teal", "#5AC8FA"),
        ("Pink", "#FF2D55"),
        ("Indigo", "#5856D6")
    ]

    var body: some View {
        Form {
            Section("Name") {
                TextField("Checklist name", text: $name)
            }

            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(iconOptions, id: \.self) { option in
                        Button {
                            icon = option
                        } label: {
                            Image(systemName: option)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(icon == option
                                              ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                                              : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(colorOptions, id: \.hex) { option in
                        Button {
                            colorHex = option.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: option.hex) ?? .accentColor)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(.white, lineWidth: colorHex == option.hex ? 3 : 0)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Schedule") {
                Picker("Frequency", selection: $scheduleType) {
                    ForEach(PrepScheduleType.allCases) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
            }

            Section("Notes") {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            if isEditing {
                Section {
                    Button(role: .destructive) {
                        if let checklist {
                            viewModel.deleteChecklist(checklist, context: viewContext)
                        }
                        dismiss()
                    } label: {
                        Label("Delete Checklist", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Checklist" : "New Checklist")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Create") {
                    save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let checklist {
                name = checklist.name
                icon = checklist.icon
                colorHex = checklist.colorHex
                scheduleType = checklist.scheduleType
                notes = checklist.notes
            }
        }
    }

    private func save() {
        if let checklist {
            // Update existing
            checklist.name = name.trimmingCharacters(in: .whitespaces)
            checklist.icon = icon
            checklist.colorHex = colorHex
            checklist.scheduleType = scheduleType
            checklist.notes = notes
            checklist.modifiedAt = Date()
            viewContext.safeSave()
            viewModel.loadData(context: viewContext)
        } else {
            // Create new
            let newChecklist = viewModel.createChecklist(
                name: name.trimmingCharacters(in: .whitespaces),
                icon: icon,
                colorHex: colorHex,
                scheduleType: scheduleType,
                context: viewContext
            )
            newChecklist.notes = notes
            viewContext.safeSave()
        }
    }
}
