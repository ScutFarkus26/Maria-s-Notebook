// ScheduleLanesSheet.swift
// The lanes: rename them, give each a color, put them in order, and add a
// person (Morah Devora). A lane can't be removed yet (the plan's Deferred list).

import SwiftUI

struct ScheduleLanesSheet: View {
    let model: SchedulesPageModel
    let onAddPerson: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edits: [SchedulesPageModel.LaneEdit] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($edits) { $edit in
                        row($edit)
                    }
                    .onMove { from, to in edits.move(fromOffsets: from, toOffset: to) }
                } footer: {
                    Text("Drag to change the order the lanes show in. Your own lane shows your planned lessons.")
                }
                Section {
                    Button("Add a Person…", systemImage: "person.badge.plus") {
                        apply()
                        onAddPerson()
                    }
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("Lanes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply() }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            edits = model.laneEdits
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
    }

    private func row(_ edit: Binding<SchedulesPageModel.LaneEdit>) -> some View {
        let lane = edit.wrappedValue
        let color = ScheduleLaneColor(rawValue: lane.colorRaw)
            ?? ScheduleLaneColor.of(TimetableLaneSnapshot(
                id: lane.id, name: lane.name, kind: lane.kind,
                sortOrder: edits.firstIndex { $0.id == lane.id } ?? 0
            ))
        return HStack(spacing: 10) {
            Menu {
                ForEach(ScheduleLaneColor.allCases) { choice in
                    Button {
                        edit.wrappedValue.colorRaw = choice.rawValue
                    } label: {
                        Label(choice.label, systemImage: choice == color ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                Circle()
                    .fill(color.color)
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("Color, \(color.label)")
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .fixedSize()
            TextField("Name", text: edit.name)
            Text(kindLabel(lane))
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func kindLabel(_ lane: SchedulesPageModel.LaneEdit) -> String {
        switch lane.kind {
        case .room: "Room"
        case .person: lane.isGuide ? "You" : "Person"
        }
    }

    private func apply() {
        // On failure the save alert says so and the sheet stays open.
        if model.applyLaneEdits(edits) { dismiss() }
    }
}
