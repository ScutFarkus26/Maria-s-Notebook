//
//  ChecklistLensControls.swift
//  Cosmic Daybook
//
//  The controls that switch the checklist's lens: a segmented "All Marks / Ready to
//  Present (12)" in the Mac and iPad toolbar, and a menu in the iPhone's header. Plus
//  the iPhone's per-row Plan, which sits by the lesson's name because the phone has
//  no Class column.
//

import SwiftUI

/// The toolbar's segmented lens picker (Mac and iPad).
struct ChecklistLensPicker: View {
    @Binding var lens: ChecklistLens
    let readyCount: Int

    var body: some View {
        Picker("Show", selection: $lens) {
            ForEach(ChecklistLens.allCases) { lens in
                Text(lens.title(readyCount: readyCount)).tag(lens)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Show every mark, or lift the children each lesson can be given to now")
    }
}

/// The iPhone header's lens menu: the same two choices, with a check on the current one.
struct ChecklistLensMenu: View {
    @Binding var lens: ChecklistLens
    let readyCount: Int

    var body: some View {
        Menu {
            Picker("Show", selection: $lens) {
                ForEach(ChecklistLens.allCases) { lens in
                    Text(lens.title(readyCount: readyCount)).tag(lens)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle" + (lens == .ready ? ".fill" : ""))
                .imageScale(.large)
        }
        .accessibilityLabel("Show")
        .accessibilityValue(lens.title(readyCount: readyCount))
    }
}

/// "Plan 5" at the end of a lesson's name on the iPhone, under the Ready lens.
struct ChecklistCompactPlanButton: View {
    let readyCount: Int
    let onPlan: () -> Void

    var body: some View {
        Button(action: onPlan) {
            Text("Plan \(readyCount)")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(.blue)
        .fixedSize()
        .accessibilityLabel("Plan for \(readyCount) ready")
    }
}

/// "Groups" beside the lens: the Groups page's ladder for a sequence on
/// screen, where the children ready for its next steps are gathered into
/// groups. One sequence on screen opens it straight away; several offer a menu.
struct ChecklistGroupsButton: View {
    let area: String
    let sequences: [String]

    @Environment(\.appRouter) private var appRouter

    /// The sequences a ladder can be drawn for: filed ones (a lesson with no
    /// sequence sits in no sub-area), as the ladder spells them.
    private var ladders: [String] {
        sequences.map { $0.trimmed() }.filter { !$0.isEmpty }
    }

    var body: some View {
        let ladders = ladders
        let area = area.trimmed()
        if !area.isEmpty, let only = ladders.first {
            if ladders.count == 1 {
                Button {
                    appRouter.navigateToGroups(area: area, sequence: only)
                } label: {
                    Label("Groups", systemImage: "person.3")
                }
                .help("Open \(only) in Groups, with the children ready for each step")
            } else {
                Menu {
                    ForEach(ladders, id: \.self) { sequence in
                        Button(sequence) { appRouter.navigateToGroups(area: area, sequence: sequence) }
                    }
                } label: {
                    Label("Groups", systemImage: "person.3")
                }
                .help("Open a sequence in Groups, with the children ready for each step")
            }
        }
    }
}
